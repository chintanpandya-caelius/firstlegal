import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import searchArticles from '@salesforce/apex/PortalHomeSearchController.searchArticles';

export default class HomePageSearch extends NavigationMixin(LightningElement) {
    articles = [];
    searchTerm = '';
    isLoading = false;
    errorMessage = '';
    hasSearched = false;
    tickets = []

    _debounceTimer;

    /* ---------- Event Handlers ---------- */

    handleInput(event) {
        this.searchTerm = event.target.value;

        if (!this.searchTerm || this.searchTerm.trim().length === 0) {
            this.handleClear();
            return;
        }

        if (this.searchTerm.trim().length < 2) return;

        clearTimeout(this._debounceTimer);
        this._debounceTimer = setTimeout(() => {
            this.performSearch();
        }, 400);
    }

    handleKeyUp(event) {
        if (event.key === 'Enter' && this.searchTerm.trim().length >= 2) {
            clearTimeout(this._debounceTimer);
            this.performSearch();
        }
    }

    handleClear() {
        this.searchTerm = '';
        this.hasSearched = false;
        this.errorMessage = '';
        this.articles = [];
        this.tickets = [];
        this.isLoading = false;
        clearTimeout(this._debounceTimer);
    }

    handleArticleClick(event) {
        event.preventDefault();
        const newId = event.currentTarget.dataset.id;
        if (!newId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: '/knowledgearticle?id=' + newId
            }
        });
    }

    handleTicketClick(event) {
        event.preventDefault();
        const ticketId = event.currentTarget.dataset.id;
        if (!ticketId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: ticketId,
                objectApiName: 'Case',
                actionName: 'view'
            }
        });
}

    /* ---------- Data ---------- */

    performSearch() {
        this.isLoading = true;
        this.errorMessage = '';
        this.hasSearched = true;

        searchArticles({ searchTerm: this.searchTerm.trim(), pageSize: 10 })
            .then((data) => {
                this.articles = this.formatArticles(data?.articles);
                this.tickets = this.formatTickets(data?.tickets);
                this.isLoading = false;
                console.log("Knowledge data fetched: ", this.articles)
                console.log("Ticket data fetched: ", this.tickets);
            })
            .catch((error) => {
                this.errorMessage = this.extractError(error);
                this.articles = [];
                this.isLoading = false;
                console.log("Got Error: ", this.tickets);
            });
    }

    /* ---------- Helpers ---------- */

    formatArticles(data) {
        if (!data || data.length === 0) return [];
        return data.map((item) => ({
            id:                 item.id,
            knowledgeArticleId: item.knowledgeArticleId,
            title:              item.title,
            urlName:            item.urlName,
            excerpt:            item.excerpt,
            lastPublishedDate:  item.lastPublishedDate,
            formattedDate:      item.lastPublishedDate
                                    ? this.formatDate(item.lastPublishedDate)
                                    : ''
        }));
    }

    formatDate(isoString) {
        try {
            return new Date(isoString).toLocaleDateString('en-US', {
                year: 'numeric',
                month: 'short',
                day: 'numeric'
            });
        } catch (e) {
            return '';
        }
    }

    extractError(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'Something went wrong. Please try again.';
    }

    formatTickets(data) {
        if (!data || data.length === 0) return [];
        return data.map((item) => ({
            id: item.id,
            caseNumber: item.caseNumber,
            subject: item.subject
        }));
    }

    /* ---------- Getters ---------- */

    get hasArticles() {
        return this.articles && this.articles.length > 0;
    }

    get showEmptyState() {
        return this.hasSearched && !this.isLoading && !this.hasArticles && !this.hasTickets && !this.errorMessage;
    }

    get showResults() {
        return this.hasSearched || this.isLoading;
    }

    get resultsLabel() {
        return `${this.articles.length} result${this.articles.length !== 1 ? 's' : ''} for "${this.searchTerm}"`;
    }

    get hasTickets() {
    return this.tickets && this.tickets.length > 0;
    }

    get articlesLabel() {
        return `${this.articles.length} result${this.articles.length !== 1 ? 's' : ''} for "${this.searchTerm}"`;
    }

    get ticketsLabel() {
        return `${this.tickets.length} result${this.tickets.length !== 1 ? 's' : ''} for "${this.searchTerm}"`;
    }
}