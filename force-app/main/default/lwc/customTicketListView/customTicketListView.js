import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getListViewOptions from '@salesforce/apex/CustomTicketListViewController.getListViewOptions';
import getTickets from '@salesforce/apex/CustomTicketListViewController.getTickets';

const DEFAULT_PAGE_SIZE = 5;
const SEARCH_DEBOUNCE_MS = 300;

export default class CustomTicketListView extends NavigationMixin(LightningElement) {
    // Experience Builder page that renders "View Your Ticket"; the record Id is passed
    // as a URL state param so the resulting link is shareable on its own.
    @api ticketDetailPageName = 'Ticket_Detail__c';
    @api ticketDetailIdParam = 'id';

    tickets = [];
    totalCount = 0;
    searchTerm = '';
    pageSize = DEFAULT_PAGE_SIZE;
    pageNumber = 1;
    selectedView = 'OPEN';
    listViewOptions = [];
    isLoading = false;
    errorMessage;

    searchTimeout;

    pageSizeOptions = [
        { label: 'Show 5', value: '5' },
        { label: 'Show 10', value: '10' },
        { label: 'Show 25', value: '25' },
        { label: 'Show 50', value: '50' }
    ];

    connectedCallback() {
        this.loadListViewOptions();
        this.loadTickets();
    }

    loadListViewOptions() {
        getListViewOptions()
            .then((options) => {
                this.listViewOptions = options;
            })
            .catch(() => {
                // fall back to the three fixed views if the status picklist read fails
                this.listViewOptions = [
                    { label: 'My Open Tickets', value: 'OPEN' },
                    { label: 'My Closed Tickets', value: 'CLOSED' },
                    { label: 'My All Tickets', value: 'ALL' }
                ];
            });
    }

    loadTickets() {
        this.isLoading = true;
        getTickets({
            selectedView: this.selectedView,
            searchTerm: this.searchTerm,
            pageSize: this.pageSize,
            pageNumber: this.pageNumber
        })
            .then((result) => {
                this.tickets = (result.tickets || []).map((t) => ({ ...t }));
                this.totalCount = result.totalCount;
                this.errorMessage = undefined;
                console.log(this.tickets);
            })
            .catch((error) => {
                this.tickets = [];
                this.totalCount = 0;
                this.errorMessage =
                    (error && error.body && error.body.message) || 'Unable to load tickets right now.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleViewChange(event) {
        this.selectedView = event.detail.value;
        this.pageNumber = 1;
        this.loadTickets();
    }

    handleSearchInput(event) {
        const value = event.target.value;
        window.clearTimeout(this.searchTimeout);
        this.searchTimeout = window.setTimeout(() => {
            this.searchTerm = value;
            this.pageNumber = 1;
            this.loadTickets();
        }, SEARCH_DEBOUNCE_MS);
    }

    handlePageSizeChange(event) {
        this.pageSize = parseInt(event.detail.value, 10);
        this.pageNumber = 1;
        this.loadTickets();
    }

    handleNext() {
        if (this.hasNextPage) {
            this.pageNumber += 1;
            this.loadTickets();
        }
    }

    handlePrevious() {
        if (this.hasPreviousPage) {
            this.pageNumber -= 1;
            this.loadTickets();
        }
    }

    handleTicketClick(event) {
        event.preventDefault();
        const ticketId = event.currentTarget.dataset.id;
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

    handleViewAll() {
    this[NavigationMixin.Navigate]({
        type: 'standard__objectPage',
        attributes: {
            objectApiName: 'Case', 
            actionName: 'list'
        },
        state: {
            filterName: this.selectedView
        }
    });
}

    get hasNextPage() {
        return this.pageNumber * this.pageSize < this.totalCount;
    }

    get hasPreviousPage() {
        return this.pageNumber > 1;
    }

    get isNextDisabled() {
        return !this.hasNextPage;
    }

    get isPreviousDisabled() {
        return !this.hasPreviousPage;
    }

    get startRecord() {
        return this.totalCount === 0 ? 0 : (this.pageNumber - 1) * this.pageSize + 1;
    }

    get endRecord() {
        const end = this.pageNumber * this.pageSize;
        return end > this.totalCount ? this.totalCount : end;
    }

    get isEmpty() {
        return !this.isLoading && this.tickets.length === 0 && !this.errorMessage;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get itemsLabel() {
        return this.totalCount === 1 ? 'item' : 'items';
    }
}