import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getRelatedArticles from '@salesforce/apex/KnowledgeRelatedArticlesController.getRelatedArticles';

export default class KnowledgeRelatedArticles extends NavigationMixin(LightningElement) {

    // ── Properties ────────────────────────────────────────────────

    articleId;
    relatedArticles = [];
    isLoading = false;

    // ── NavigationMixin: Navigate to article detail page with id in URL ─

    handleArticleClick(event) {
        event.preventDefault();
        const newId = event.currentTarget.dataset.id;
        if (!newId || newId === this.articleId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: '/knowledgearticle?id=' + newId
            }
        });
    }

    // ── Read ?id= from /knowledgearticle URL ──────────────────────

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (pageRef && pageRef.state) {
            const id = pageRef.state.id || pageRef.state.c__id;
            if (id && id !== this.articleId) {
                this.articleId = id;
                this.relatedArticles = [];
                this.loadRelatedArticles();
            }
        }
    }

    // ── Fetch related articles ────────────────────────────────────

    loadRelatedArticles() {
        this.isLoading = true;

        getRelatedArticles({ articleId: this.articleId })
            .then(results => {
                this.relatedArticles = results.map(a => ({
                    ...a,
                    href: `/knowledgearticle?id=${a.Id}`
                }));
                this.isLoading = false;
            })
            .catch(error => {
                console.error('KnowledgeRelatedArticles error:', error);
                this.isLoading = false;
            });
    }

    // ── Computed ──────────────────────────────────────────────────

    get hasRelatedArticles() {
        return this.relatedArticles && this.relatedArticles.length > 0;
    }
}