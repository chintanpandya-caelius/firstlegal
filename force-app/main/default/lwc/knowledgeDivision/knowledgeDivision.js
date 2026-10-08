import { LightningElement, wire, api } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getDivisionPage from '@salesforce/apex/KnowledgeBaseController.getDivisionPage';
import KnowledgeBaseDivisionLogos from '@salesforce/resourceUrl/KnowledgeBaseDivisionLogos';

const DEFAULT_ARTICLE_PAGE_PATH = '/knowledgearticle';
const DEFAULT_HOME_PAGE_NAME = 'Knowledge_Base__c';
const DEFAULT_DIVISION_PAGE_NAME = 'Knowledge_Division__c';
const DEFAULT_PAGE_SIZE = 10;
const SORT_MOST_VIEWED = 'MOST_VIEWED';
const SORT_RECENTLY_ADDED = 'RECENTLY_ADDED';
const SORT_A_Z = 'A_Z';

export default class KnowledgeDivision extends NavigationMixin(LightningElement) {
    divisionValue = '';
    currentDivision = null;
    articles = [];
    otherDivisions = [];
    totalVisibleArticleCount = 0;
    searchTerm = '';
    sortOption = SORT_MOST_VIEWED;
    pageSize = DEFAULT_PAGE_SIZE;
    offset = 0;
    hasMore = false;
    isLoading = true;
    errorMessage = '';
    invalidDivision = false;
    _debounceTimer;
    _pageInitialized = false;

    /** Experience Builder page API name of the Knowledge Base home page. */
    @api homePageName = DEFAULT_HOME_PAGE_NAME;

    /** Experience Builder page API name of the division page. */
    @api divisionPageName = DEFAULT_DIVISION_PAGE_NAME;

    /** Existing article detail page path. */
    @api articlePagePath = DEFAULT_ARTICLE_PAGE_PATH;

    get hasArticles() {
        return this.articles.length > 0;
    }

    get hasOtherDivisions() {
        return this.otherDivisions.length > 0;
    }

    get showLoadingState() {
        return this.isLoading;
    }

    get showErrorState() {
        return !this.isLoading && Boolean(this.errorMessage);
    }

    get showInvalidDivisionState() {
        return !this.isLoading && this.invalidDivision;
    }

    get showEmptyState() {
        return !this.isLoading && !this.invalidDivision && !this.errorMessage && !this.hasArticles;
    }

    get articleCountLabel() {
        const count = Number(this.totalVisibleArticleCount) || 0;
        return `${count} ${count === 1 ? 'article' : 'articles'}`;
    }

    get sortOptions() {
        return [
            { label: 'Most viewed', value: SORT_MOST_VIEWED },
            { label: 'Recently Added', value: SORT_RECENTLY_ADDED },
            { label: 'A — Z', value: SORT_A_Z }
        ];
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        const nextDivision = pageRef?.state?.c__division || pageRef?.state?.division;
        if (!nextDivision) {
            this.isLoading = false;
            this.invalidDivision = true;
            return;
        }

        if (this._pageInitialized && nextDivision === this.divisionValue) {
            return;
        }

        this._pageInitialized = true;
        this.divisionValue = nextDivision;
        this.offset = 0;
        this.searchTerm = '';
        this.loadDivision();
    }

    disconnectedCallback() {
        clearTimeout(this._debounceTimer);
    }

    handleInput(event) {
        this.searchTerm = event.target.value;

        if (!this.searchTerm || this.searchTerm.trim().length === 0) {
            this.handleClear();
            return;
        }

        if (this.searchTerm.trim().length < 2) {
            return;
        }

        clearTimeout(this._debounceTimer);
        this.offset = 0;
        this._debounceTimer = setTimeout(() => {
            this.performSearch();
        }, 400);
    }

    handleKeyUp(event) {
        if (event.key === 'Enter' && this.searchTerm.trim().length >= 2) {
            clearTimeout(this._debounceTimer);
            this.offset = 0;
            this.performSearch();
        }
    }

    handleClear() {
        clearTimeout(this._debounceTimer);
        this.searchTerm = '';
        this.offset = 0;
        this.errorMessage = '';
        this.loadDivision();
    }

    handleSortChange(event) {
        this.sortOption = event.target.value || SORT_MOST_VIEWED;
        this.offset = 0;
        this.loadDivision();
    }

    handleLoadMore() {
        if (this.isLoading || !this.hasMore) {
            return;
        }

        this.offset += this.pageSize;
        this.loadDivision(true);
    }

    handleArticleClick(event) {
        event.preventDefault();
        const articleId = event.currentTarget.dataset.id;
        if (!articleId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: `${this.articlePagePath}?c__id=${encodeURIComponent(articleId)}`
            }
        });
    }

    handleOtherDivisionClick(event) {
        event.preventDefault();
        const division = event.currentTarget.dataset.division;
        if (!division) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: this.divisionPageName
            },
            state: {
                c__division: division
            }
        });
    }


    performSearch() {
        this.loadDivision();
    }

    loadDivision(append = false) {
        if (!this.divisionValue) {
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        this.invalidDivision = false;

        getDivisionPage({
            division: this.divisionValue,
            searchTerm: this.searchTerm.trim(),
            sortOption: this.sortOption,
            pageSize: this.pageSize,
            offset: this.offset
        })
            .then((data) => {
                if (data.invalidDivision) {
                    this.currentDivision = null;
                    this.articles = [];
                    this.otherDivisions = [];
                    this.totalVisibleArticleCount = 0;
                    this.hasMore = false;
                    this.invalidDivision = true;
                    this.isLoading = false;
                    return;
                }

                this.currentDivision = this.decorateDivision(data.currentDivision);
                const nextArticles = (data.articles || []).map((article) => this.decorateArticle(article));
                this.articles = append ? [...this.articles, ...nextArticles] : nextArticles;
                this.otherDivisions = (data.otherDivisions || []).map((division) => this.decorateDivision(division));
                this.totalVisibleArticleCount = data.totalVisibleArticleCount || 0;
                this.hasMore = Boolean(data.hasMore);
                this.pageSize = data.pageSize || this.pageSize;
                this.offset = data.offset || 0;
                this.invalidDivision = false;
                this.isLoading = false;
            })
            .catch((error) => {
                this.currentDivision = null;
                this.articles = [];
                this.otherDivisions = [];
                this.totalVisibleArticleCount = 0;
                this.hasMore = false;
                this.errorMessage = this.extractError(error);
                this.isLoading = false;
            });
    }

    decorateDivision(division) {
        if (!division) {
            return null;
        }

        return {
            ...division,
            logoUrl: this.buildLogoUrl(division.logoPath),
            articleCountLabel: `${division.articleCount} ${division.articleCount === 1 ? 'article' : 'articles'}`
        };
    }

    decorateArticle(article) {
        return {
            ...article,
            articleUrl: `${this.articlePagePath}?c__id=${encodeURIComponent(article.id)}`,
            updatedLabel: article.lastPublishedDate
                ? this.formatDate(article.lastPublishedDate)
                : ''
        };
    }

    buildLogoUrl(logoPath) {
        if (!logoPath) {
            return KnowledgeBaseDivisionLogos;
        }

        return `${KnowledgeBaseDivisionLogos}/${logoPath.replace(/^\/+/, '')}`;
    }

    formatDate(value) {
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) {
            return '';
        }

        const differenceMs = Date.now() - date.getTime();
        if (differenceMs < 0) {
            return 'just now';
        }

        const minutes = Math.floor(differenceMs / 60000);
        if (minutes < 60) {
            return minutes <= 1 ? 'just now' : `${minutes} minutes ago`;
        }

        const hours = Math.floor(minutes / 60);
        if (hours < 24) {
            return hours === 1 ? '1 hour ago' : `${hours} hours ago`;
        }

        const days = Math.floor(hours / 24);
        if (days < 7) {
            return days === 1 ? '1 day ago' : `${days} days ago`;
        }

        const weeks = Math.floor(days / 7);
        if (weeks < 5) {
            return weeks === 1 ? '1 week ago' : `${weeks} weeks ago`;
        }

        const months = Math.floor(days / 30);
        if (months < 12) {
            return months === 1 ? '1 month ago' : `${months} months ago`;
        }

        return new Intl.DateTimeFormat('en', {
            day: 'numeric',
            month: 'short',
            year: 'numeric'
        }).format(date);
    }

    extractError() {
        return 'Unable to load this Knowledge Base topic. Please try again later.';
    }
}