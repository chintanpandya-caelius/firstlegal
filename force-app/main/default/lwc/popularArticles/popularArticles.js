import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPopularArticles from '@salesforce/apex/PopularArticlesController.getPopularArticles';

// Experience Builder page API name for the Knowledge detail page.
// Change here if the page is renamed - nothing else needs to move.
const KNOWLEDGE_DETAIL_PAGE = 'Knowledge_Detail__c';

export default class PopularArticles extends NavigationMixin(LightningElement) {
    articles = [];
    hasError = false;

    @wire(getPopularArticles)
    wiredArticles({ data, error }) {
        if (data) {
            this.articles = data.map((a) => ({
                ...a,
                viewCountLabel: this.formatCount(a.viewCount),
                showStatusBadge: a.publishStatus && a.publishStatus !== 'Online'
            }));
            this.hasError = false;
        } else if (error) {
            this.hasError = true;
            this.articles = [];
            // eslint-disable-next-line no-console
            console.error('Error loading popular articles', error);
        }
    }

    get hasArticles() {
        return this.articles && this.articles.length > 0;
    }

    get isEmpty() {
        return !this.hasError && this.articles && this.articles.length === 0;
    }

    formatCount(count) {
        return count >= 1000 ? (count / 1000).toFixed(1).replace('.0', '') + 'k' : String(count);
    }

    handleArticleClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.recordid;

        if (!recordId) {
            console.error('PopularArticles: no recordid on the clicked element');
            return;
        }

        // this[NavigationMixin.Navigate]({
        //     type: 'comm__namedPage',
        //     attributes: { name: KNOWLEDGE_DETAIL_PAGE },
        //     state: { c__recordId: recordId }
        // });

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: '/knowledgearticle?id=' + recordId
            }
        });
    }
}