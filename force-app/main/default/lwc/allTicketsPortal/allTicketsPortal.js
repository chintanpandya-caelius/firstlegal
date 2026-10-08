import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTickets from '@salesforce/apex/TicketPortalController.getTickets';

export default class AllTicketsPortal extends NavigationMixin(LightningElement) {
    @track tickets = [];
    @track totalRecords = 0;
    @track pageSize = '5';
    @track pageNumber = 1;
    @track searchTerm = '';
    @track filterType = 'My Open';

    filterOptions = [
        { label: 'My Open Tickets', value: 'My Open' },
        { label: 'My Closed Tickets', value: 'My Close' },
        { label: 'All Company Tickets', value: 'My All' }
    ];

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
        getTickets({
            pageSize: parseInt(this.pageSize, 10),
            pageNumber: this.pageNumber,
            searchTerm: this.searchTerm,
            filterType: this.filterType
        })
        .then(result => {
            this.tickets = result.tickets;
            this.totalRecords = result.totalRecords;
        })
        .catch(error => {
            console.error('Error tracking dashboard data records:', error);
        });
    }

    handleFilterChange(event) {
        this.filterType = event.target.value;
        this.pageNumber = 1; 
        this.fetchTicketData();
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.pageNumber = 1;
        this.fetchTicketData();
    }

    handlePageSizeChange(event) {
        this.pageSize = event.target.value;
        this.pageNumber = 1;
        this.fetchTicketData();
    }

    handlePrevious() {
        if (this.pageNumber > 1) {
            this.pageNumber--;
            this.fetchTicketData();
        }
    }

    handleNext() {
        if (this.pageNumber < this.totalPages) {
            this.pageNumber++;
            this.fetchTicketData();
        }
    }

    navigateToTicketDetail(event) {
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: 'Case',
                actionName: 'view'
            }
        });
    }

    handleViewAllRoute() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Case',
                actionName: 'list'
            },
            state: {
                filterName: 'Recent'
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
}