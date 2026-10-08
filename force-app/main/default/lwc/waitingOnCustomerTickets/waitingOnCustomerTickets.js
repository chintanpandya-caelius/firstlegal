import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTickets from '@salesforce/apex/TicketPortalController.getTickets';

const DEFAULT_PAGE_SIZE = '5';
const SEARCH_DEBOUNCE_MS = 300;
const FILTER_TYPE_WAITING_ON_CUSTOMER = 'Waiting on Customer';

export default class WaitingOnCustomerTickets extends NavigationMixin(LightningElement) {
    tickets = [];
    totalRecords = 0;
    pageSize = DEFAULT_PAGE_SIZE;
    pageNumber = 1;
    searchTerm = '';
    isLoading = false;
    errorMessage = '';

    searchDebounceTimeout;

    pageSizeOptions = [
        { label: '5', value: '5' },
        { label: '10', value: '10' },
        { label: '25', value: '25' },
        { label: '50', value: '50' }
    ];

    connectedCallback() {
        this.fetchTicketData();
    }

    fetchTicketData() {
        this.isLoading = true;
        this.errorMessage = '';

        getTickets({
            pageSize: parseInt(this.pageSize, 10),
            pageNumber: this.pageNumber,
            searchTerm: this.searchTerm,
            filterType: FILTER_TYPE_WAITING_ON_CUSTOMER
        })
            .then((result) => {
                this.tickets = result.tickets;
                this.totalRecords = result.totalRecords;
            })
            .catch((error) => {
                this.tickets = [];
                this.totalRecords = 0;
                this.errorMessage = this.reduceError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSearchChange(event) {
        const value = event.target.value;
        window.clearTimeout(this.searchDebounceTimeout);
        this.searchDebounceTimeout = window.setTimeout(() => {
            this.searchTerm = value;
            this.pageNumber = 1;
            this.fetchTicketData();
        }, SEARCH_DEBOUNCE_MS);
    }

    handlePageSizeChange(event) {
        this.pageSize = event.detail.value;
        this.pageNumber = 1;
        this.fetchTicketData();
    }

    handlePrevious() {
        if (this.pageNumber > 1) {
            this.pageNumber -= 1;
            this.fetchTicketData();
        }
    }

    handleNext() {
        if (this.pageNumber < this.totalPages) {
            this.pageNumber += 1;
            this.fetchTicketData();
        }
    }

    navigateToTicketDetail(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Ticket_Detial__c'
            },
            state: {
                recordId
            }
        });
    }

    get totalPages() {
        return Math.ceil(this.totalRecords / parseInt(this.pageSize, 10)) || 1;
    }

    get isFirstPage() {
        return this.pageNumber === 1;
    }

    get isLastPage() {
        return this.pageNumber >= this.totalPages;
    }

    get hasTickets() {
        return this.tickets.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    // get showEmptyState() {
    //     return !this.isLoading && !this.hasError && !this.hasTickets;
    // }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unknown error occurred while loading tickets.';
    }
}