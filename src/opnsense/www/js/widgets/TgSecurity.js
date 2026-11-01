
export default class TgSecurity extends BaseTableWidget {
    constructor() {
        super();
        this.tickTimeout = 30;
    }

    getMarkup() {
        let $container = $('<div></div>');
        $container.append(this.createTable('tg-security-table', {headerPosition: 'left'}));
        return $container;
    }

    static esc(v) {
        return $('<div/>').text(v === undefined || v === null ? '' : String(v)).html();
    }

    async onWidgetTick() {
        const data = await this.ajaxCall('/api/telegramalerts/dashboard/summary');
        if (!data || !data.security) {
            return;
        }
        const s = data.security;
        const e = TgSecurity.esc;
        const failing = (s.failing || []).length;
        const rows = [
            [[this.translations.firehol], e(s.firehol)],
            [[this.translations.ids], `<span class="${s.ids_today > 0 ? 'text-warning' : 'text-success'}">${e(s.ids_today)}</span>`],
            [[this.translations.failed], `<span class="${s.failed_logins_today > 0 ? 'text-danger' : 'text-success'}">${e(s.failed_logins_today)}</span>`],
            [[this.translations.change], e(s.last_change)],
            [[this.translations.checks], `<span class="${failing ? 'text-danger' : 'text-success'}">${e(s.checks)}</span>` +
                (failing ? '<br/><small>' + s.failing.map(f => e(f)).join('<br/>') + '</small>' : '')],
            [[this.translations.lastalert], e(s.last_alert)],
        ];
        super.updateTable('tg-security-table', rows);
    }
}
