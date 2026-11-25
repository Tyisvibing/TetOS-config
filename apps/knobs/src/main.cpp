// knobs — any config file as a settings menu, explained from its own docs.

#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>

#include "backend.h"
#include "cli.h"
#include "portalfilepicker.h"
#include "theme.h"
#include "translator.h"

int main(int argc, char *argv[]) {
    QStringList arguments;
    for (int i = 0; i < argc; ++i) arguments.append(QString::fromLocal8Bit(argv[i]));

    // Commands for scripts and agents run without a display.
    const bool command = Cli::isCommand(arguments);
    if (command)
        qputenv("QT_QPA_PLATFORM", "offscreen");

    QGuiApplication app(argc, argv);
    app.setApplicationName("knobs");
    app.setApplicationVersion("0.1.0");

    // Matches the window to knobs.desktop, so the compositor (Wayland app_id)
    // and the launcher pick up the installed icon.
    app.setDesktopFileName("knobs");
    app.setWindowIcon(QIcon::fromTheme("knobs"));

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    if (command) {
        // Explanations come back in the desktop's language for the CLI too.
        return Cli::run(arguments, translator.language());
    }

    QQuickStyle::setStyle("Material");

    Theme theme;
    Backend backend(new PortalFilePicker);
    backend.setLanguage(translator.language());
    QObject::connect(&translator, &Translator::changed, &backend,
                     [&] { backend.setLanguage(translator.language()); });

    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    // `knobs <file>` and `knobs open <file>` open straight into the file.
    QString file = arguments.value(1);
    if (file == "open") file = arguments.value(2);
    if (!file.isEmpty())
        backend.openFile(file);

    return app.exec();
}
