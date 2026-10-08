import { LightningElement, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { wire } from 'lwc';
import getKnowledgeArticle from '@salesforce/apex/KnowledgeArticleDetailController.getKnowledgeArticle';

export default class KnowledgeArticleDetail extends LightningElement {

    article;
    isLoading = false;
    errorMessage;
    selectedRating = 0;
    ratingSubmitted = false;

    articleId;

    // Read the current page reference to extract the 'id' URL param
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (pageRef && pageRef.state) {
            // Supports ?id=XXXX or c__id=XXXX (Experience Cloud namespaced params)
            const id = pageRef.state.id || pageRef.state.c__id;
            if (id && id !== this.articleId) {
                this.articleId = id;
                this.loadArticle();
            }
        }
    }

    loadArticle() {
        this.isLoading = true;
        this.article = null;
        this.errorMessage = null;

        getKnowledgeArticle({ articleId: this.articleId })
            .then(result => {
                this.article = result;
                this.isLoading = false;
            })
            .catch(error => {
                this.errorMessage = 'Unable to load article. Please try again.';
                console.error('KnowledgeArticleDetail error:', error);
                this.isLoading = false;
            });
    }

    // ── Meta helpers ──────────────────────────────────────────────

    get lastUpdatedLabel() {
        if (!this.article || !this.article.LastPublishedDate) return '';
        const updated = new Date(this.article.LastPublishedDate);
        const now = new Date();
        const diffMs = now - updated;
        const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

        if (diffDays === 0) return 'today';
        if (diffDays === 1) return '1 day ago';
        if (diffDays < 30) return `${diffDays} days ago`;
        if (diffDays < 60) return '1 month ago';
        const diffMonths = Math.floor(diffDays / 30);
        return `${diffMonths} months ago`;
    }

    get readTime() {
        if (!this.article || !this.article.Answer__c) return null;
        // Strip HTML tags, count words, assume 200 wpm
        const text = this.article.Answer__c.replace(/<[^>]*>/g, '');
        const wordCount = text.trim().split(/\s+/).length;
        const minutes = Math.max(1, Math.round(wordCount / 200));
        return minutes;
    }

    // ── Star rating ───────────────────────────────────────────────

    get stars() {
        return [1, 2, 3, 4, 5].map(i => ({
            index: i,
            cssClass: i <= this.selectedRating ? 'star star-filled' : 'star star-empty'
        }));
    }

    handleStarClick(event) {
        if (this.ratingSubmitted) return;
        const rating = parseInt(event.currentTarget.dataset.index, 10);
        this.selectedRating = rating;
        this.ratingSubmitted = true;

        // Optional: call an Apex method to persist the rating
        // submitRating({ articleId: this.articleId, rating: rating });
    }
}