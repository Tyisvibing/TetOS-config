QT += core gui quick quickcontrols2 testlib dbus
CONFIG += c++17 testcase
TARGET = knobs_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += ../src/analyzer.h ../src/backend.h ../src/configdocument.h ../src/filepicker.h \
           ../src/optionsmodel.h ../src/store.h ../src/theme.h ../src/translator.h
SOURCES += knobs_tests.cpp ../src/analyzer.cpp ../src/backend.cpp ../src/configdocument.cpp \
           ../src/optionsmodel.cpp ../src/store.cpp ../src/theme.cpp ../src/translator.cpp
RESOURCES += ../src/resources.qrc
