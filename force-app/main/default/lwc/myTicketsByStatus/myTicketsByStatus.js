import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getTicketCountByStatus from '@salesforce/apex/MyTicketsController.getTicketCountByStatus';

const STATUS_ORDER = [
    'New', 'Assigned', 'In Progress',
    'Waiting On Customer', 'Waiting on 3rd Party',
    'Resolved', 'Closed'
];

export default class MyTicketsByStatus extends LightningElement {
    chartData    = [];
    isLoading    = true;
    error        = undefined;
    lastRefreshed;
    _wiredResult;

    connectedCallback() {
        this.lastRefreshed = this._formattedTime();
    }

    @wire(getTicketCountByStatus)
    wiredTickets(result) {
        this._wiredResult = result;           
        const { error, data } = result;

        if (data) {
            this.chartData = this._buildChartData(data);
            this.error     = undefined;
        } else if (error) {
            this.error     = error?.body?.message ?? 'An unexpected error occurred.';
            this.chartData = [];
        }
        this.isLoading = false;              // set AFTER processing
    }

    _buildChartData(data) {
       
        const statusMap = Object.fromEntries(
            data.map(({ status, count }) => [status, count])
        );

        const ordered = [
            ...STATUS_ORDER.filter(s => statusMap[s] !== undefined)
                           .map(s => ({ status: s, count: statusMap[s] })),
            ...Object.keys(statusMap)
                     .filter(s => !STATUS_ORDER.includes(s))
                     .map(s => ({ status: s, count: statusMap[s] }))
        ];

        const maxCount = ordered.reduce((max, r) => Math.max(max, r.count), 1);

        return ordered.map(({ status, count }) => ({
            id:       status,                // stable key — not array index
            status,
            count,
            barStyle: `width: ${Math.round((count / maxCount) * 100)}%`,
            ariaLabel: `${status}: ${count} ticket${count !== 1 ? 's' : ''}`
        }));
    }

    get totalTickets() {
        return this.chartData.reduce((sum, row) => sum + row.count, 0);
    }

    get hasData() {
        return this.chartData.length > 0;
    }

    async handleRefresh() {
        this.isLoading    = true;
        this.lastRefreshed = this._formattedTime();
        try {
            await refreshApex(this._wiredResult);  // actually re-fetches
        } finally {
            this.isLoading = false;
        }
    }

    _formattedTime() {
        return new Date().toLocaleTimeString([], {
            hour:   '2-digit',
            minute: '2-digit'
        });
    }
}