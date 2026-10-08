import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin }             from 'lightning/navigation';
import getSuggestedArticles            from '@salesforce/apex/PublicKnowledgeArticleController.getSuggestedArticles';
import searchPublicArticles            from '@salesforce/apex/PublicKnowledgeArticleController.searchPublicArticles';

const MIN_SEARCH_LENGTH  = 2;
const SEARCH_DEBOUNCE_MS = 300;

export default class PublicSupportPopup extends NavigationMixin(LightningElement) {

    // ─── EXPERIENCE BUILDER CONFIG ────────────────────────────────────────────
    @api kbPageName        = '';
    @api announcementsPage = '';
    @api guidedToursPage   = '';
    @api contactUsPage     = '';
    @api supportEmail      = '';
    @api supportPhone      = '';
    @api popupTitle        = 'First Connect Support Center';
    @api popupTagline      = 'We\'d love to hear from you. Ask us anything, or share your feedback.';

    // ─── STATE ────────────────────────────────────────────────────────────────
    isPopupOpen    = false;
    currentScreen  = 'home';
    searchTerm     = '';
    searchResults  = [];
    isSearching    = false;
    suggestedError = undefined;
    _searchTimeout = null;

    // ─── WIRE: Suggested Articles (uses LDS cache correctly) ──────────────────
    suggestedArticles = [];

    @wire(getSuggestedArticles)
    wiredSuggested({ data, error }) {
        if (data) {
            this.suggestedArticles = data;
            this.suggestedError    = undefined;
        } else if (error) {
            this.suggestedError    = error?.body?.message ?? 'Failed to load suggested articles.';
            this.suggestedArticles = [];
        }
    }

    // ─── LIFECYCLE ────────────────────────────────────────────────────────────
    disconnectedCallback() {
        // Prevent callbacks firing against a detached component
        if (this._searchTimeout) {
            clearTimeout(this._searchTimeout);
        }
    }

    // ─── SCREEN FLAGS ─────────────────────────────────────────────────────────
    get showHome()          { return this.currentScreen === 'home'; }
    get showKnowledgeBase() { return this.currentScreen === 'knowledgeBase'; }
    get showSearch()        { return this.currentScreen === 'search'; }

    // ─── MENU VISIBILITY ──────────────────────────────────────────────────────
    get showAnnouncements() { return !!this.announcementsPage; }
    get showGuidedTours()   { return !!this.guidedToursPage; }
    get showKbMenuItem()    { return !!this.kbPageName; }
    get showEmail()         { return !!this.supportEmail; }
    get showPhone()         { return !!this.supportPhone; }
    get showChat()          { return !!this.contactUsPage; }
    get showContactRow()    { return this.showEmail || this.showPhone || this.showChat; }

    // ─── ARTICLE DISPLAY ──────────────────────────────────────────────────────
    get displayArticles() {
        return this.currentScreen === 'search'
            ? this.searchResults
            : this.suggestedArticles;
    }

    get hasNoResults() {
        return !this.isSearching && this.displayArticles.length === 0;
    }

    // ─── POPUP CONTROLS ───────────────────────────────────────────────────────
    togglePopup() {
        this.isPopupOpen = !this.isPopupOpen;
        if (!this.isPopupOpen) this._resetState();
    }

    closePopup() {
        this.isPopupOpen = false;
        this._resetState();
    }

    _resetState() {
        this.currentScreen = 'home';
        this.searchTerm    = '';
        this.searchResults = [];
        this.isSearching   = false;
    }

    // ─── SCREEN NAVIGATION ────────────────────────────────────────────────────
    goHome() {
        // Full reset — not just searchTerm — so stale results don't linger
        this._resetState();
    }

    goToKnowledgeBase() { this.currentScreen = 'knowledgeBase'; }
    goToSearch()        { this.currentScreen = 'search'; }

    goToAnnouncements() {
        if (!this.announcementsPage) return;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: this.announcementsPage }
        });
        this.closePopup();
    }

    goToGuidedTours() {
        if (!this.guidedToursPage) return;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: this.guidedToursPage }
        });
        this.closePopup();
    }

    // ─── ARTICLE NAVIGATION ───────────────────────────────────────────────────
    handleArticleClick(event) {
        const urlName = event.currentTarget.dataset.url;
        this[NavigationMixin.Navigate]({
            type: 'standard__knowledgeArticlePage',
            attributes: { urlName }
        });
        this.closePopup();
    }

    handleViewAllArticles() {
        if (!this.kbPageName) return;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: this.kbPageName }
        });
        this.closePopup();
    }

    // ─── SEARCH ───────────────────────────────────────────────────────────────
    handleSearch(event) {
        // Use event.detail.value for lightning-input; event.target.value for plain <input>
        this.searchTerm = event.detail?.value ?? event.target.value;

        clearTimeout(this._searchTimeout);
        this._searchTimeout = setTimeout(() => this._runSearch(), SEARCH_DEBOUNCE_MS);
    }

    _runSearch() {
        if (!this.searchTerm || this.searchTerm.trim().length < MIN_SEARCH_LENGTH) {
            this.searchResults = [];
            this.isSearching   = false;
            return;
        }

        this.isSearching = true;

        searchPublicArticles({ searchTerm: this.searchTerm.trim(), pageSize: 10 })
            .then(data => {
                this.searchResults = data;
            })
            .catch(error => {
                console.error('Search error:', error?.body?.message ?? error);
                this.searchResults = [];
            })
            .finally(() => {
                this.isSearching = false;
            });
    }

    // ─── CONTACT ──────────────────────────────────────────────────────────────
    handleEmail() {
        if (!this.supportEmail) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: `mailto:${this.supportEmail}` }
        });
    }

    handleCall() {
        if (!this.supportPhone) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: `tel:${this.supportPhone}` }
        });
    }

    handleChat() {
        if (!this.contactUsPage) return;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: this.contactUsPage }
        });
        this.closePopup();
    }
}