import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getTicketDetail from '@salesforce/apex/TicketDetailController.getTicketDetail';
import getCaseComments from '@salesforce/apex/TicketDetailController.getCaseComments';
import postComment     from '@salesforce/apex/TicketDetailController.postComment';
import getAttachments  from '@salesforce/apex/TicketDetailController.getAttachments';
import getFileUrls     from '@salesforce/apex/TicketDetailController.getFileUrls';

const NO_RECORD_ID = 'No ticket was specified. Please return home and pick a ticket.';

export default class TicketDetail extends NavigationMixin(LightningElement) {

    recordId;
    pageRefResolved = false;

    ticket         = null;
    rawComments    = [];
    rawAttachments = [];
    newComment     = '';
    isPosting      = false;
    isLoading      = true;
    errorMessage   = '';

    // Kept so refreshApex can force a fresh server read after posting,
    // instead of re-invoking the cacheable method (which can return the
    // stale cached list right after an insert).
    wiredCommentsResult;

    // Resolves the record id from every page shape this component can sit on:
    //   object / record page  -> attributes.recordId
    //   named page + state    -> state.recordId
    //   legacy links          -> state.c__recordId
    // Without the state fallbacks, a link built with query params leaves
    // recordId undefined, the wires never fire, and the spinner spins forever.
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) {
            return;
        }
        this.pageRefResolved = true;

        const id =
            pageRef.attributes?.recordId ||
            pageRef.state?.recordId ||
            pageRef.state?.c__recordId;

        if (id) {
            if (id !== this.recordId) {
                this.recordId = id;
                this.errorMessage = '';
                this.isLoading = true;
            }
        } else {
            // Nothing to load - stop the spinner and say why.
            this.isLoading = false;
            this.errorMessage = NO_RECORD_ID;
        }
    }

    @wire(getTicketDetail, { recordId: '$recordId' })
    wiredTicket({ data, error }) {
        if (!this.recordId) {
            return;
        }
        this.isLoading = false;

        if (data) {
            this.ticket = {
                caseNumber         : data.CaseNumber,
                subject            : data.Subject,
                openedDate         : data.CreatedDate,
                status             : data.Status,
                priority           : data.Priority,
                type               : data.Type,
                dueDate            : data.ClosedDate,
                subType            : data.Ticket_SubType__c,
                matterNumber       : data.Matter_Number__c,
                externalCaseNumber : data.Court_Case_Number__c,
                description        : data.Description,
                createdByName      : data.CreatedBy ? data.CreatedBy.Name : ''
            };
            this.errorMessage = '';
        } else if (error) {
            this.ticket = null;
            this.errorMessage = this._extractError(error);
            console.error('Ticket detail error', JSON.stringify(error));
        }
    }

    @wire(getCaseComments, { ticketId: '$recordId' })
    wiredComments(result) {
        this.wiredCommentsResult = result;
        if (result.data) {
            console.log(result.data);
            this.rawComments = result.data;
        } else if (result.error) {
            this.rawComments = [];
            console.error('Load shared notes error', result.error);
        }
    }

    @wire(getAttachments, { recordId: '$recordId' })
    wiredAttachments({ data, error }) {
        if (data) {
            this.rawAttachments = data;
        } else if (error) {
            console.error('Attachments error', error);
            if (!this.errorMessage) {
                this.errorMessage = this._extractError(error);
            }
        }
    }

    // ── Derived state ─────────────────────────────────────────────
    getInitials(name) {
        const parts = (name || 'U').trim().split(/\s+/);

        if (parts.length === 1) {
            return parts[0].slice(0, 2).toUpperCase();
        }

        return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
    }

    get activities() {
        return (this.rawComments || []).map(note => {
            const authorName = note.CreatedBy?.Name || 'Unknown User';

            return {
                ...note,
                body: note.Body__c || '',
                authorName,
                initials: this.getInitials(authorName)
            };
        });
    }

    get hasActivities() {
        return this.activities.length > 0;
    }

    get formattedAttachments() {
        return this.rawAttachments
            .filter((a) => a.ContentDocument)
            .map((a) => ({
                contentDocumentId : a.ContentDocumentId,
                contentVersionId  : a.ContentDocument.LatestPublishedVersionId,
                title             : a.ContentDocument.Title,
                fileExtension     : a.ContentDocument.FileExtension,
                uploadDate        : a.ContentDocument.CreatedDate,
                sizeLabel         : this._formatSize(a.ContentDocument.ContentSize)
            }));
    }

    get hasAttachments() {
        return this.formattedAttachments.length > 0;
    }

    get isPostDisabled() {
        return this.isPosting || !this.newComment || !this.newComment.trim();
    }

    // True only once we know there is nothing to show - keeps the template
    // from flashing an error banner before the page ref has arrived.
    get showError() {
        return !this.isLoading && !this.ticket && !!this.errorMessage;
    }

    // ── Handlers ──────────────────────────────────────────────────

    handleCommentChange(e) {
        this.newComment = e.target.value;
    }

    async handlePost() {
        if (this.isPostDisabled) {
            return;
        }
        this.isPosting = true;
        try {
            await postComment({ ticketId: this.recordId, body: this.newComment });
            this.newComment = '';
            // Force a fresh server read of the (cacheable) comments wire
            // instead of calling getCaseComments imperatively, which can
            // hand back a stale cached result right after the insert.
            await refreshApex(this.wiredCommentsResult);
            this.errorMessage = '';
        } catch (err) {
            console.error('Post comment error', err);
            this.errorMessage = this._extractError(err);
        } finally {
            this.isPosting = false;
        }
    }

    // Preview opens the ContentDistribution's public "view in browser"
    // URL in a new tab. The tab is opened SYNCHRONOUSLY on the click
    // (before the await), then redirected once the Apex call resolves.
    // Opening it after the await breaks the browser's "user gesture"
    // association with the click, so window.open gets silently blocked
    // by the popup blocker - which is why Preview looked like it was
    // doing nothing.

    // Debugged till here -- Kishlaya
    async handlePreviewClick(event) {
        const contentVersionId = event.currentTarget.dataset.versionId;
        if (!contentVersionId) {
            console.error('Preview: no versionId on the clicked element');
            return;
        }
        const newTab = window.open('', '_blank');
        try {
            const urls = await getFileUrls({ contentVersionId });
            if (newTab) {
                newTab.location = urls.previewUrl;
            } else {
                this.errorMessage = 'Please allow popups for this site to preview files.';
            }
        } catch (err) {
            if (newTab) {
                newTab.close();
            }
            console.error('Preview error', err);
            this.errorMessage = this._extractError(err);
        }
    }

    async handleDownloadClick(event) {
        // Stop the click from bubbling to the card's onclick (preview).
        event.preventDefault();
        event.stopPropagation();

        const contentVersionId = event.currentTarget.dataset.versionId;
        if (!contentVersionId) {
            console.error('Download: no versionId on the clicked element');
            return;
        }
        // Same synchronous window.open fix as handlePreviewClick - see
        // comment above for why this has to happen before the await.
        const newTab = window.open('', '_blank');
        try {
            const urls = await getFileUrls({ contentVersionId });
            if (newTab) {
                newTab.location = urls.downloadUrl;
            } else {
                this.errorMessage = 'Please allow popups for this site to download files.';
            }
        } catch (err) {
            if (newTab) {
                newTab.close();
            }
            console.error('Download error', err);
            this.errorMessage = this._extractError(err);
        }
    }

    handleBackClick() {
        this[NavigationMixin.Navigate]({
            type       : 'comm__namedPage',
            attributes : { name : 'Home' }
        });
    }

    // Same navigation shape popularArticles uses, so a ticket can link
    // straight into a related knowledge article.
    handleArticleClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.recordid;
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type       : 'comm__namedPage',
            attributes : { name : 'Knowledge_Detail__c' },
            state      : { recordId : recordId }
        });
    }

    // ── Helpers ───────────────────────────────────────────────────

    _formatSize(bytes) {
        if (!bytes) return '';
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + ' MB';
        if (bytes >= 1024)    return (bytes / 1024).toFixed(0) + ' KB';
        return bytes + ' B';
    }

    _initials(name) {
        if (!name) return '?';
        const parts = name.trim().split(' ');
        return parts.length >= 2
            ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
            : name.substring(0, 2).toUpperCase();
    }

    _extractError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return "We couldn't load this ticket. Please try again.";
    }
}