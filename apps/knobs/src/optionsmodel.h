#pragma once

#include <QAbstractListModel>
#include <QSortFilterProxyModel>

#include "configdocument.h"

// Every option of the open document, for the settings list.
class OptionsModel : public QAbstractListModel {
    Q_OBJECT

public:
    enum Role {
        KeyRole = Qt::UserRole + 1, NameRole, SectionRole, TypeRole, DescriptionRole, DefaultRole,
        ValueRole, ChoicesRole, IsSetRole, LineRole, MinimumRole, MaximumRole, IndexRole,
    };

    explicit OptionsModel(const ConfigDocument *document, QObject *parent = nullptr)
        : QAbstractListModel(parent), m_document(document) {}

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // The document's options were replaced, or edited in place.
    void reset();
    void refresh();

private:
    const ConfigDocument *m_document;
};

// The list as shown: one section (or every set option) and a search.
class OptionsFilter : public QSortFilterProxyModel {
    Q_OBJECT
    Q_PROPERTY(QString section READ section WRITE setSection NOTIFY changed)
    Q_PROPERTY(QString search READ search WRITE setSearch NOTIFY changed)
    Q_PROPERTY(bool setOnly READ setOnly WRITE setSetOnly NOTIFY changed)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit OptionsFilter(QObject *parent = nullptr);

    QString section() const { return m_section; }
    QString search() const { return m_search; }
    bool setOnly() const { return m_setOnly; }
    int count() const { return rowCount(); }
    void setSection(const QString &section);
    void setSearch(const QString &search);
    void setSetOnly(bool setOnly);

    // Maps a row in the filtered list to the option's index in the document.
    Q_INVOKABLE int optionAt(int row) const;
    Q_INVOKABLE int rowOf(int option) const;

signals:
    void changed();
    void countChanged();

protected:
    bool filterAcceptsRow(int row, const QModelIndex &parent) const override;

private:
    void apply();

    QString m_section;
    QString m_search;
    bool m_setOnly = false;
};
