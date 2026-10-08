import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin }             from 'lightning/navigation';
import getSuggestedArticles            from '@salesforce/apex/PublicKnowledgeArticleController.getSuggestedArticles';
import searchPublicArticles            from '@salesforce/apex/PublicKnowledgeArticleController.searchPublicArticles';

const MIN_SEARCH_LENGTH  = 2;
const SEARCH_DEBOUNCE_MS = 300;

export default class PublicSupportPopup extends NavigationMixin(LightningElement) {

    // ─── EXPERIENCE BUILDER CONFIG ────────────────────────────────────────────
    @api kbPageName        = 'Knowledge_Base__c';
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
    suggestedArticles = [];
    _searchTimeout = null;

    // ─── CHAT-OPEN STATE ────────────────────────────────────────────────────
    isChatOpen = false;

    // ─── WIRE: 3 Suggested Articles (always loaded) ───────────────────────────
    @wire(getSuggestedArticles)
    wiredSuggested({ data, error }) {
        if (data) {
            this.suggestedArticles = data;
        } else if (error) {
            console.error('Suggested articles error:', error);
            this.suggestedArticles = [];
        }
    }

    connectedCallback() {
        this._handleChatMaximized = () => { this.isChatOpen = true; };
        this._handleChatMinimized = () => { this.isChatOpen = false; };

        window.addEventListener('onEmbeddedMessagingWindowMaximized', this._handleChatMaximized);
        window.addEventListener('onEmbeddedMessagingWindowMinimized', this._handleChatMinimized);
    }

    disconnectedCallback() {
        if (this._searchTimeout) clearTimeout(this._searchTimeout);
        window.removeEventListener('onEmbeddedMessagingWindowMaximized', this._handleChatMaximized);
        window.removeEventListener('onEmbeddedMessagingWindowMinimized', this._handleChatMinimized);
    }

    // ─── COMPUTED PROPERTIES ──────────────────────────────────────────────────
    get showHome()          { return this.currentScreen === 'home'; }
    get showKnowledgeBase() { return this.currentScreen === 'knowledgeBase'; }
    get showAnnouncements() { return !!this.announcementsPage; }
    get showGuidedTours()   { return !!this.guidedToursPage; }
    get showKbMenuItem()    { return !!this.kbPageName; }
    get showEmail()         { return !!this.supportEmail; }
    get showPhone()         { return !!this.supportPhone; }
    get showChat()          { return !!this.contactUsPage; }
    get showContactRow()    { return this.showEmail || this.showPhone || this.showChat; }

    get hasSuggestedArticles() {
        return this.suggestedArticles && this.suggestedArticles.length > 0;
    }

    get displayArticles() {
        if (this.searchTerm.length >= MIN_SEARCH_LENGTH && this.searchResults.length > 0) {
            return this.searchResults;
        }
        return this.suggestedArticles;
    }

    get sectionTitle() {
        return (this.searchTerm.length >= MIN_SEARCH_LENGTH && this.searchResults.length > 0)
            ? 'Search Results'
            : 'Suggested Articles';
    }

    get hasNoResults() {
        return !this.isSearching
            && this.searchTerm.length >= MIN_SEARCH_LENGTH
            && this.searchResults.length === 0;
    }

    // ─── DYNAMIC CLASSES ────────────────────────────────────────────────────
    get fabClass() {
        return 'support-fab' + (this.isChatOpen ? ' chat-open' : '');
    }

    get popupClass() {
        return 'popup-wrapper' + (this.isChatOpen ? ' chat-open' : '');
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
        this.currentScreen = 'home';
        this.searchTerm    = '';
        this.searchResults = [];
    }

    goToKnowledgeBase() {
        this.currentScreen = 'knowledgeBase';
    }

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

    // ─── SEARCH ───────────────────────────────────────────────────────────────
    handleSearch(event) {
        this.searchTerm = event.target.value;
        if (this._searchTimeout) clearTimeout(this._searchTimeout);

        this._searchTimeout = setTimeout(() => {
            this._runSearch();
        }, SEARCH_DEBOUNCE_MS);
    }

    _runSearch() {
        const cleanTerm = this.searchTerm ? this.searchTerm.trim() : '';
        if (cleanTerm.length < MIN_SEARCH_LENGTH) {
            this.searchResults = [];
            this.isSearching   = false;
            return;
        }

        this.isSearching = true;
        searchPublicArticles({ searchTerm: cleanTerm, pageSize: 10 })
            .then(data => {
                this.searchResults = data;
            })
            .catch(error => {
                console.error('Search error:', error);
                this.searchResults = [];
            })
            .finally(() => {
                this.isSearching = false;
            });
    }

    // ─── ARTICLE CLICK → Navigate to /knowledgearticle?id=recordId ────────────
    handleArticleClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: '/knowledgearticle?id=' + recordId
            }
        });
        this.closePopup();
    }

    // ─── VIEW ALL → Navigate to Knowledge_Base__c page ────────────────────────
    handleViewAllArticles() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: this.kbPageName }
        });
        this.closePopup();
    }

    // ─── CONTACT HANDLERS ─────────────────────────────────────────────────────
    handleEmail() {
        if (!this.supportEmail) return;
        window.location.href = 'mailto:' + this.supportEmail;
    }

    handleCall() {
        if (!this.supportPhone) return;
        window.location.href = 'tel:' + this.supportPhone;
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