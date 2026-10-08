import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPopularArticles from '@salesforce/apex/PopularArticlesController.getPopularArticles';

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
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: '/knowledgearticle?id=' + recordId
            }
        });
    }
}