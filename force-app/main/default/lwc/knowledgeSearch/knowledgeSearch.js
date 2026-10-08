import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import searchArticles from '@salesforce/apex/PortalKnowledgeSearchController.searchArticles';

export default class KnowledgeSearch extends NavigationMixin(LightningElement) {
    articles = [];
    searchTerm = '';
    isLoading = false;
    errorMessage = '';
    hasSearched = false;

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

    /* ---------- Data ---------- */

    performSearch() {
        this.isLoading = true;
        this.errorMessage = '';
        this.hasSearched = true;

        searchArticles({ searchTerm: this.searchTerm.trim(), pageSize: 10 })
            .then((data) => {
                this.articles = this.formatArticles(data);
                this.isLoading = false;
            })
            .catch((error) => {
                this.errorMessage = this.extractError(error);
                this.articles = [];
                this.isLoading = false;
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

    /* ---------- Getters ---------- */

    get hasArticles() {
        return this.articles && this.articles.length > 0;
    }

    get showEmptyState() {
        return this.hasSearched && !this.isLoading && !this.hasArticles && !this.errorMessage;
    }

    get showResults() {
        return this.hasSearched || this.isLoading;
    }

    get resultsLabel() {
        return `${this.articles.length} result${this.articles.length !== 1 ? 's' : ''} for "${this.searchTerm}"`;
    }
}