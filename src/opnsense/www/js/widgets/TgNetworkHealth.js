
export default class TgNetworkHealth extends BaseTableWidget {
    constructor() {
        super();
        this.tickTimeout = 30;
    }

    getMarkup() {
        let $container = $('<div></div>');
        $container.append(this.createTable('tg-health-table', {headerPosition: 'left'}));
        return $container;
    }

    static esc(v) {
        return $('<div/>').text(v === undefined || v === null ? '' : String(v)).html();
    }

    static badge(text, ok) {
        return `<span class="label label-${ok ? 'success' : 'danger'}">${TgNetworkHealth.esc(text)}</span>`;
    }

    async onWidgetTick() {
        const data = await this.ajaxCall('/api/telegramalerts/dashboard/summary');
        if (!data || !data.health) {
            return;
        }
        const h = data.health;
        const e = TgNetworkHealth.esc;
        const lat = parseFloat(h.latency);
        const loss = parseFloat(h.loss);
        const rows = [
            [[this.translations.internet], TgNetworkHealth.badge(h.internet === 'up' ? 'Online' : 'Offline', h.internet === 'up')],
            [[this.translations.wanip], e(h.wan_ip)],
            [[this.translations.latency], `<span class="${lat > 100 ? 'text-danger' : (lat > 40 ? 'text-warning' : 'text-success')}">${e(h.latency)}</span> <small class="text-muted">${e(h.gateway || '')}</small>`],
            [[this.translations.loss], `<span class="${loss > 1 ? 'text-danger' : 'text-success'}">${e(h.loss)}</span>`],
            [[this.translations.outages], e(h.outages_24h)],
            [[this.translations.lastoutage], e(h.last_outage)],
            [[this.translations.uptime], e(h.uptime)],
            [[this.translations.temp], `<span class="${parseFloat(h.cpu_temp) >= 75 ? 'text-danger' : ''}">${e(h.cpu_temp)}</span>`],
        ];
        super.updateTable('tg-health-table', rows);
    }
}
