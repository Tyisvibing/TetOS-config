#include "optionsmodel.h"

int OptionsModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : int(m_document->options.size());
}

QVariant OptionsModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_document->options.size())
        return {};
    const Option &o = m_document->options.at(index.row());
    switch (role) {
    case KeyRole: return o.key;
    case NameRole: return o.name;
    case SectionRole: return o.section;
    case TypeRole: return o.type;
    case DescriptionRole: return o.description;
    case DefaultRole: return o.defaultValue;
    case ValueRole: return o.isSet() ? o.value() : o.defaultValue;
    case ChoicesRole: return o.choices;
    case IsSetRole: return o.isSet();
    case LineRole: return o.line;
    case MinimumRole: return o.minimum;
    case MaximumRole: return o.maximum;
    case IndexRole: return index.row();
    }
    return {};
}

QHash<int, QByteArray> OptionsModel::roleNames() const {
    return {
        {KeyRole, "key"}, {NameRole, "name"}, {SectionRole, "section"}, {TypeRole, "type"},
        {DescriptionRole, "description"}, {DefaultRole, "defaultValue"}, {ValueRole, "value"},
        {ChoicesRole, "choices"}, {IsSetRole, "isSet"}, {LineRole, "line"}, {MinimumRole, "minimum"},
        {MaximumRole, "maximum"}, {IndexRole, "optionIndex"},
    };
}

void OptionsModel::reset() {
    beginResetModel();
    endResetModel();
}

void OptionsModel::refresh() {
    // Inserting or removing a line renumbers the options below it, so every
    // row may have changed; signalling them in place keeps the list's scroll.
    if (rowCount() > 0)
        emit dataChanged(index(0), index(rowCount() - 1));
}

OptionsFilter::OptionsFilter(QObject *parent) : QSortFilterProxyModel(parent) {
    setFilterCaseSensitivity(Qt::CaseInsensitive);
    connect(this, &QAbstractItemModel::rowsInserted, this, &OptionsFilter::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &OptionsFilter::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &OptionsFilter::countChanged);
    connect(this, &QAbstractItemModel::layoutChanged, this, &OptionsFilter::countChanged);
}

void OptionsFilter::setSection(const QString &section) {
    if (section == m_section) return;
    m_section = section;
    apply();
}

void OptionsFilter::setSearch(const QString &search) {
    if (search == m_search) return;
    m_search = search;
    apply();
}

void OptionsFilter::setSetOnly(bool setOnly) {
    if (setOnly == m_setOnly) return;
    m_setOnly = setOnly;
    apply();
}

void OptionsFilter::apply() {
    beginFilterChange();
    endFilterChange(QSortFilterProxyModel::Direction::Rows);
    emit changed();
    emit countChanged();
}

int OptionsFilter::optionAt(int row) const {
    const QModelIndex source = mapToSource(index(row, 0));
    return source.isValid() ? source.row() : -1;
}

int OptionsFilter::rowOf(int option) const {
    if (!sourceModel() || option < 0) return -1;
    const QModelIndex mapped = mapFromSource(sourceModel()->index(option, 0));
    return mapped.isValid() ? mapped.row() : -1;
}

bool OptionsFilter::filterAcceptsRow(int row, const QModelIndex &parent) const {
    const QModelIndex index = sourceModel()->index(row, 0, parent);
    // A search looks across every section, since you rarely know where an
    // option lives.
    if (!m_search.isEmpty()) {
        for (int role : {OptionsModel::KeyRole, OptionsModel::DescriptionRole, OptionsModel::SectionRole})
            if (index.data(role).toString().contains(m_search, Qt::CaseInsensitive))
                return true;
        return false;
    }
    if (m_setOnly)
        return index.data(OptionsModel::IsSetRole).toBool();
    return m_section.isEmpty() || index.data(OptionsModel::SectionRole).toString() == m_section;
}
