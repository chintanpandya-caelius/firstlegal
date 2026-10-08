import { LightningElement, wire, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getDivisionOverview from '@salesforce/apex/KnowledgeBaseController.getDivisionOverview';
import KnowledgeBaseDivisionLogos from '@salesforce/resourceUrl/KnowledgeBaseDivisionLogos';

const DEFAULT_DIVISION_PAGE_NAME = 'Knowledge_Division__c';
const LOAD_ERROR = 'Unable to load the Knowledge Base. Please try again later.';

export default class KnowledgeBase extends NavigationMixin(LightningElement) {
    divisions = [];
    isLoading = true;
    errorMessage = '';

    /**
     * Experience Builder page API name for the division page.
     * Kept configurable because the actual page API name is project-specific.
     */
    @api divisionPageName = DEFAULT_DIVISION_PAGE_NAME;

    @wire(getDivisionOverview)
    wiredDivisions({ data, error }) {
        if (data) {
            this.divisions = data.map((division) => ({
                ...division,
                logoUrl: this.buildLogoUrl(division.logoPath),
                articleCountLabel: `${division.articleCount} ${division.articleCount === 1 ? 'article' : 'articles'}`
            }));
            this.errorMessage = '';
            this.isLoading = false;
            return;
        }

        if (error) {
            this.divisions = [];
            this.errorMessage = LOAD_ERROR;
            this.isLoading = false;
        }
    }

    buildLogoUrl(logoPath) {
        if (!logoPath) {
            return KnowledgeBaseDivisionLogos;
        }

        return `${KnowledgeBaseDivisionLogos}/${logoPath.replace(/^\/+/, '')}`;
    }

    get hasDivisions() {
        return this.divisions.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get showEmptyState() {
        return !this.isLoading && !this.hasError && !this.hasDivisions;
    }

    handleDivisionClick(event) {
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

    handleDivisionKeydown(event) {
        if (event.key !== 'Enter' && event.key !== ' ') {
            return;
        }

        event.preventDefault();
        event.currentTarget.click();
    }
}