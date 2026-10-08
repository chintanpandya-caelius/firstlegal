import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getArticleBreadcrumbContext from '@salesforce/apex/KnowledgeBaseController.getArticleBreadcrumbContext';

const DEFAULT_HOME_PAGE_NAME = 'Knowledge_Base__c';
const DEFAULT_DIVISION_PAGE_NAME = 'Knowledge_Division__c';

export default class KnowledgeBreadCrumbs extends NavigationMixin(LightningElement) {
    @api articleId;
    @api division;
    @api divisionLabel;
    @api articleTitle;
    @api homePageName = DEFAULT_HOME_PAGE_NAME;
    @api divisionPageName = DEFAULT_DIVISION_PAGE_NAME;

    resolvedArticleId = '';
    resolvedDivision = '';
    resolvedDivisionLabel = '';
    resolvedArticleTitle = '';
    isLoading = false;
    errorMessage = '';
    _initialized = false;

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        const state = pageRef?.state || {};
        const stateArticleId = state.c__id || state.id;
        const stateDivision = state.c__division || state.division;

        this.resolvedArticleId = this.articleId || stateArticleId || '';
        this.resolvedDivision = this.division || stateDivision || '';
        this.resolvedDivisionLabel = this.divisionLabel || this.resolvedDivision;
        this.resolvedArticleTitle = this.articleTitle || '';

        if (!this.resolvedArticleId) {
            this.isLoading = false;
            this._initialized = true;
            return;
        }

        if (this._initialized && this.articleId === this.resolvedArticleId && this.resolvedArticleTitle) {
            return;
        }

        this._initialized = true;
        this.loadArticleContext();
    }

    connectedCallback() {
        if (this.articleId) {
            this.resolvedArticleId = this.articleId;
        }
        if (this.division) {
            this.resolvedDivision = this.division;
        }
        if (this.divisionLabel) {
            this.resolvedDivisionLabel = this.divisionLabel;
        }
        if (this.articleTitle) {
            this.resolvedArticleTitle = this.articleTitle;
        }
    }

    get isArticleBreadcrumb() {
        return Boolean(this.resolvedArticleId);
    }

    get showDivisionBreadcrumb() {
        return Boolean(this.resolvedDivision || this.resolvedDivisionLabel);
    }

    get showArticleBreadcrumb() {
        return this.isArticleBreadcrumb && Boolean(this.resolvedArticleTitle);
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    loadArticleContext() {
        this.isLoading = true;
        this.errorMessage = '';

        getArticleBreadcrumbContext({ articleId: this.resolvedArticleId })
            .then((data) => {
                if (!data) {
                    this.errorMessage = 'Article breadcrumb information is not available.';
                    this.isLoading = false;
                    return;
                }

                this.resolvedArticleTitle = data.articleTitle || '';
                this.resolvedDivision = data.divisionValue || '';
                this.resolvedDivisionLabel = data.divisionLabel || data.divisionValue || '';
                this.isLoading = false;
            })
            .catch(() => {
                this.errorMessage = 'Article breadcrumb information is not available.';
                this.isLoading = false;
            });
    }

    handleHomeClick(event) {
        event.preventDefault();

        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: this.homePageName
            }
        });
    }

    handleDivisionClick(event) {
        event.preventDefault();

        if (!this.resolvedDivision) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: this.divisionPageName
            },
            state: {
                c__division: this.resolvedDivision
            }
        });
    }
}