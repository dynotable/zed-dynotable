use std::{env, fs, path::Path};

use zed_extension_api::{self as zed, LanguageServerId, LanguageServerInstallationStatus, Result};

const BINARY_NAME: &str = "dynotable-lsp";
const PACKAGE_NAME: &str = "dynotable-cli";
const SCRIPT_PATH: &str = "node_modules/dynotable-cli/bin/dynotable-lsp.mjs";

/// The command that starts the language server.
///
/// The script path is absolute because Zed does not start the server in the
/// extension's work directory, where npm installed the package.
pub fn server_command(
    path_binary: Option<String>,
    node: String,
    cwd: &Path,
) -> (String, Vec<String>) {
    match path_binary {
        Some(binary) => (binary, Vec::new()),
        None => (
            node,
            vec![cwd.join(SCRIPT_PATH).to_string_lossy().into_owned()],
        ),
    }
}

fn script_exists() -> bool {
    fs::metadata(SCRIPT_PATH).is_ok_and(|stat| stat.is_file())
}

fn set_status(id: &LanguageServerId, status: LanguageServerInstallationStatus) {
    zed::set_language_server_installation_status(id, &status);
}

fn fail(id: &LanguageServerId, message: String) -> String {
    set_status(
        id,
        LanguageServerInstallationStatus::Failed(message.clone()),
    );
    message
}

struct DynoTableExtension {
    checked_for_update: bool,
}

impl DynoTableExtension {
    fn install_script(&mut self, id: &LanguageServerId) -> Result<()> {
        let installed_script = script_exists();
        if self.checked_for_update && installed_script {
            return Ok(());
        }

        set_status(id, LanguageServerInstallationStatus::CheckingForUpdate);
        let latest = match zed::npm_package_latest_version(PACKAGE_NAME) {
            Ok(version) => version,
            Err(error) if installed_script => {
                set_status(
                    id,
                    LanguageServerInstallationStatus::Failed(format!(
                        "could not check for a {PACKAGE_NAME} update, using the installed version: {error}"
                    )),
                );
                return Ok(());
            }
            Err(error) => {
                return Err(fail(
                    id,
                    format!("could not get the latest {PACKAGE_NAME} version: {error}"),
                ))
            }
        };

        let installed = zed::npm_package_installed_version(PACKAGE_NAME).map_err(|error| {
            fail(
                id,
                format!("could not read the installed {PACKAGE_NAME} version: {error}"),
            )
        })?;
        if !installed_script || installed.as_deref() != Some(latest.as_str()) {
            set_status(id, LanguageServerInstallationStatus::Downloading);
            zed::npm_install_package(PACKAGE_NAME, &latest).map_err(|error| {
                fail(
                    id,
                    format!("could not install {PACKAGE_NAME} {latest}: {error}"),
                )
            })?;
            if !script_exists() {
                return Err(fail(
                    id,
                    format!("{PACKAGE_NAME} {latest} does not contain {SCRIPT_PATH}"),
                ));
            }
        }

        set_status(id, LanguageServerInstallationStatus::None);
        self.checked_for_update = true;
        Ok(())
    }
}

impl zed::Extension for DynoTableExtension {
    fn new() -> Self {
        Self {
            checked_for_update: false,
        }
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let cwd = env::current_dir().map_err(|error| error.to_string())?;
        let path_binary = worktree.which(BINARY_NAME);
        let node = if path_binary.is_some() {
            String::new()
        } else {
            self.install_script(language_server_id)?;
            zed::node_binary_path()?
        };
        let (command, args) = server_command(path_binary, node, &cwd);
        Ok(zed::Command {
            command,
            args,
            env: Default::default(),
        })
    }
}

zed::register_extension!(DynoTableExtension);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_binary_wins_and_gets_no_args() {
        let (command, args) = server_command(
            Some("/opt/homebrew/bin/dynotable-lsp".to_string()),
            "/zed/node/bin/node".to_string(),
            Path::new("/zed/work/dynotable"),
        );
        assert_eq!(command, "/opt/homebrew/bin/dynotable-lsp");
        assert!(args.is_empty());
    }

    #[test]
    fn npm_script_path_is_absolute_under_cwd() {
        let (command, args) = server_command(
            None,
            "/zed/node/bin/node".to_string(),
            Path::new("/zed/work/dynotable"),
        );
        assert_eq!(command, "/zed/node/bin/node");
        assert_eq!(
            args,
            vec!["/zed/work/dynotable/node_modules/dynotable-cli/bin/dynotable-lsp.mjs"]
        );
    }
}
