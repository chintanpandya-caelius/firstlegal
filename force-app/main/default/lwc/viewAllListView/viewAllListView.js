import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';

import getListViewOptions from '@salesforce/apex/CustomTicketListViewController.getListViewOptions';
import getAllTickets from '@salesforce/apex/CustomTicketListViewController.getAllTickets';
import getTicketExportData from '@salesforce/apex/TicketExportController.getTicketExportData';

const SEARCH_DEBOUNCE_MS = 300;

export default class CustomTicketAllListView extends NavigationMixin(LightningElement) {

    selectedView = 'OPEN';

    listViewOptions = [];

    tickets = [];
    totalCount = 0;

    searchTerm = '';

    isLoading = false;
    errorMessage;

    searchTimeout;

    showExportModal = false;
    isExporting = false;

    /*
     * Future export functionality.
     *
     * Contains ONLY the Case/Ticket record IDs
     * currently selected by the user.
     */
    selectedTicketIds = [];

    /*
     * Read filterName from the Experience Cloud URL.
     */
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {

        if (!pageRef) {
            return;
        }

        const viewFromUrl = pageRef.state?.filterName;

        if (!viewFromUrl) {
            return;
        }

        this.selectedView = viewFromUrl;

        this.loadTickets();
    }

   connectedCallback() {
        this.loadListViewOptions();
    }

    /*
     * Load the list-view labels.
     *
     * We use this only to display the selected
     * list view name in the disabled combobox.
     */
    loadListViewOptions() {

        getListViewOptions()
            .then((options) => {
                this.listViewOptions = options || [];
            })
            .catch(() => {
                this.listViewOptions = [
                    {
                        label: 'My Open Tickets',
                        value: 'OPEN'
                    },
                    {
                        label: 'My Closed Tickets',
                        value: 'CLOSED'
                    },
                    {
                        label: 'All My Tickets',
                        value: 'ALL'
                    }
                ];
            });
    }

    /*
     * Load ALL records belonging to the selected view.
     */
    loadTickets() {

        this.isLoading = true;

        getAllTickets({
            selectedView: this.selectedView,
            searchTerm: this.searchTerm
        })
            .then((result) => {

                this.tickets = (result.tickets || []).map((ticket) => ({
                    ...ticket,

                    isSelected:
                        this.selectedTicketIds.includes(
                            ticket.ticketId
                        )
                }));

                this.totalCount = result.totalCount || 0;

                this.errorMessage = undefined;
            })
            .catch((error) => {

                this.tickets = [];
                this.totalCount = 0;

                this.errorMessage =
                    (error &&
                        error.body &&
                        error.body.message) ||
                    'Unable to load tickets right now.';
            })
            .finally(() => {

                this.isLoading = false;
            });
    }

    /*
     * Search.
     */
    handleSearchInput(event) {

        const value = event.target.value;

        window.clearTimeout(this.searchTimeout);

        this.searchTimeout = window.setTimeout(() => {

            this.searchTerm = value;

            this.loadTickets();

        }, SEARCH_DEBOUNCE_MS);
    }

    /*
     * Checkbox handling.
     */
    handleTicketSelection(event) {

        const ticketId = event.target.dataset.id;
        const isChecked = event.target.checked;

        if (!ticketId) {
            return;
        }

        if (isChecked) {

            if (!this.selectedTicketIds.includes(ticketId)) {

                this.selectedTicketIds = [
                    ...this.selectedTicketIds,
                    ticketId
                ];
            }

        } else {

            this.selectedTicketIds =
                this.selectedTicketIds.filter(
                    (id) => id !== ticketId
                );
        }

        /*
         * Keep the UI state synchronized.
         */
        this.tickets = this.tickets.map((ticket) => {

            if (ticket.ticketId === ticketId) {

                return {
                    ...ticket,
                    isSelected: isChecked
                };
            }

            return ticket;
        });
    }

    handleSelectAll(event) {

        const isChecked = event.target.checked;

        /*
        * We intentionally work ONLY with the tickets currently
        * displayed in the component.
        *
        * This means Select All respects the current search filter.
        */
        const visibleTicketIds = this.tickets.map(
            (ticket) => ticket.ticketId
        );

        if (isChecked) {

            /*
            * Add every visible ticket to the master selection array.
            *
            * Tickets that were already selected stay selected.
            * Tickets outside the current search result remain untouched.
            */
            this.selectedTicketIds = [
                ...new Set([
                    ...this.selectedTicketIds,
                    ...visibleTicketIds
                ])
            ];

        } else {

            /*
            * Remove ONLY the currently visible tickets.
            *
            * Any selected tickets hidden by the current search
            * remain selected.
            */
            this.selectedTicketIds =
                this.selectedTicketIds.filter(
                    (id) => !visibleTicketIds.includes(id)
                );
        }

        /*
        * Update the checkbox state of every currently visible row.
        */
        this.tickets = this.tickets.map((ticket) => ({
            ...ticket,
            isSelected: isChecked
        }));

    }

    /*
     * Navigate to Ticket record.
     */
    handleTicketClick(event) {

        event.preventDefault();

        const ticketId =
            event.currentTarget.dataset.id;

        if (!ticketId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: ticketId,
                objectApiName: 'Case',
                actionName: 'view'
            }
        });
    }

    /*
     * Return to Home.
     */
    handleHome() {

        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Home'
            }
        });
    }

    handleExport() {
        this.showExportModal = true;
    }

    handleExportModalClose() {
        this.showExportModal = false;
    }

    handleExportConfirm(event) {
        const { format, fields } = event.detail;
        this.showExportModal = false;
        this.isExporting = true;

        const dataPromise =
            this.selectedTicketIds.length > 0
                ? getTicketExportData({
                    ticketIds: this.selectedTicketIds,
                    fieldApiNames: fields.map((f) => f.apiName)
                })
                : Promise.resolve([]); // no selection -> header-only, skip the server call entirely

        dataPromise
            .then((rows) => {
                console.log("Data was retrieved from Apex: ", rows);
                const stamp = new Date().toISOString().slice(0, 10);
                console.log("Stamp suceeded");
                if (format === 'CSV') {
                    console.log("CSV file download started");
                    this.downloadFile(
                        this.buildCsv(fields, rows),
                        `Tickets_${stamp}.csv`,
                        'text/csv;charset=utf-8;'
                    );
                    console.log("CSV file download finished");
                } else {
                    console.log("Excel file download started");
                    this.downloadFile(
                        this.buildExcelXml(fields, rows),
                        `Tickets_${stamp}.xls`,
                        'application/vnd.ms-excel'
                    );
                    console.log("Excel file download finished");
                }
            })
            .catch((error) => {
                    this.errorMessage =
                        (error && error.body && error.body.message) ||
                        'Export failed. Please try again.';
            })
            .finally(() => {
                this.isExporting = false;
            });
    }

    /*
     * The disabled combobox gets exactly one option:
     * the list view from which View All was clicked.
     */
    get currentViewOption() {
        const selectedOption = this.listViewOptions.find(option => option.value === this.selectedView);
        const label = selectedOption ? selectedOption.label : '';
        return label;
    }

    get isEmpty() {

        return (
            !this.isLoading &&
            this.tickets.length === 0 &&
            !this.errorMessage
        );
    }

    get hasError() {

        return !!this.errorMessage;
    }

    get itemsLabel() {

        return this.totalCount === 1
            ? 'item'
            : 'items';
    }

    get areAllVisibleSelected() {

    if (this.tickets.length === 0) {
        return false;
    }
    
    return this.tickets.every(
        (ticket) =>
            this.selectedTicketIds.includes(
                ticket.ticketId
            )
    );
}

// Utility functions for CSV and Excel exports
escapeCsvValue = (value) => {
    if (value === null || value === undefined) {
        return '';
    }
    const str = String(value);
    return /[",\n\r]/.test(str) ? `"${str.replace(/"/g, '""')}"` : str;
};

buildCsv(fields, rows) {
    const header = fields.map((f) => this.escapeCsvValue(f.label)).join(',');
    const dataRows = rows.map((row) =>
        fields.map((f) => this.escapeCsvValue(row[f.apiName])).join(',')
    );
    return [header, ...dataRows].join('\r\n');
}

escapeXml = (value) => {
    if (value === null || value === undefined) {
        return '';
    }
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&apos;');
};

// Builds a SpreadsheetML (Excel 2003 XML) workbook. Excel opens this
// natively — no SheetJS or other static resource needed.
buildExcelXml(fields, rows) {
    const headerCells = fields
        .map((f) => `<Cell><Data ss:Type="String">${this.escapeXml(f.label)}</Data></Cell>`)
        .join('');
    const bodyRows = rows
        .map((row) => {
            const cells = fields
                .map((f) => {
                    const val = row[f.apiName];
                    const type = typeof val === 'number' ? 'Number' : 'String';
                    return `<Cell><Data ss:Type="${type}">${this.escapeXml(val)}</Data></Cell>`;
                })
                .join('');
            return `<Row>${cells}</Row>`;
        })
        .join('');

    return (
        '<?xml version="1.0"?>' +
        '<?mso-application progid="Excel.Sheet"?>' +
        '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" ' +
        'xmlns:o="urn:schemas-microsoft-com:office:office" ' +
        'xmlns:x="urn:schemas-microsoft-com:office:excel" ' +
        'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">' +
        '<Worksheet ss:Name="Tickets"><Table>' +
        `<Row>${headerCells}</Row>${bodyRows}` +
        '</Table></Worksheet></Workbook>'
    );
}

downloadFile(content, fileName, mimeType) {
    const blob = new Blob([content], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = fileName;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
}
}