import BaseTableWidget from "./BaseTableWidget.js";

export default class TgClients extends BaseTableWidget {
    constructor() {
        super();
        this.tickTimeout = 30;
    }

    getMarkup() {
        let $container = $('<div></div>');
        $container.append(this.createTable('tg-clients-table', {headerPosition: 'left'}));
        return $container;
    }

    static esc(v) {
        return $('<div/>').text(v === undefined || v === null ? '' : String(v)).html();
    }

    async onWidgetTick() {
        const data = await this.ajaxCall('/api/telegramalerts/dashboard/summary');
        if (!data || !data.clients) {
            return;
        }
        const c = data.clients;
        const e = TgClients.esc;
        const rows = [[[this.translations.online], `<b>${e(c.online)}</b>`]];
        for (const [net, n] of Object.entries(c.per_network || {})) {
            rows.push([[`&nbsp;&nbsp;${e(net)}`], e(n)]);
        }
        rows.push([[this.translations.leases], e(c.dhcp_leases)]);
        rows.push([[this.translations.vpn], e(c.vpn)]);
        const recent = (c.recent || []).map(r => e(r)).join('<br/>');
        rows.push([[this.translations.recent], recent || `<span class="text-muted">${e(this.translations.none)}</span>`]);
        super.updateTable('tg-clients-table', rows);
    }
}
