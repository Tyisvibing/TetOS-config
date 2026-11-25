QT += core gui qml quick quickcontrols2 dbus

CONFIG += c++17 release
TARGET = knobs
TEMPLATE = app

HEADERS += \
    src/analyzer.h \
    src/backend.h \
    src/cli.h \
    src/configdocument.h \
    src/filepicker.h \
    src/optionsmodel.h \
    src/portalfilepicker.h \
    src/store.h \
    src/theme.h \
    src/translator.h

SOURCES += \
    src/main.cpp \
    src/analyzer.cpp \
    src/backend.cpp \
    src/cli.cpp \
    src/configdocument.cpp \
    src/optionsmodel.cpp \
    src/portalfilepicker.cpp \
    src/store.cpp \
    src/theme.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc
