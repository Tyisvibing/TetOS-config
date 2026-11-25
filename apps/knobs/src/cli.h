#pragma once

#include <QStringList>

// Commands that need no display: explain, get, set, unset, skill install.
namespace Cli {

// True when the arguments name a command rather than a file to open.
bool isCommand(const QStringList &arguments);
// Explanations are written in `language`, the desktop's Omarchy language.
int run(const QStringList &arguments, const QString &language);

} // namespace Cli
