import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

import SHARED_NOTE_OBJECT from '@salesforce/schema/SharedNote__c';
import NOTE_TYPE_FIELD from '@salesforce/schema/SharedNote__c.Note_Type__c';

import createSharedNote from '@salesforce/apex/SharedNoteController.createSharedNote';
import getSharedNotes from '@salesforce/apex/SharedNoteController.getSharedNotes';
import getUserTagOptions from '@salesforce/apex/SharedNoteController.getUserTagOptions';

const PAGE_SIZE = 10;
const INTERNAL_NOTE = 'Internal Note';

export default class SharedNoteForm extends LightningElement {
    @api recordId;

    body = '';
    noteType = 'External Note';
    isSaving = false;

    noteTypeOptions = [];

    userTagId = null;
    userTagOptions = [];

    notes = [];
    isLoadingNotes = false;
    isLoadingMore = false;
    hasMoreNotes = true;

    lastCreatedDate = null;
    lastNoteId = null;

    initializedRecordId = null;
    notesObserver = null;

    @wire(getObjectInfo, { objectApiName: SHARED_NOTE_OBJECT })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$defaultRecordTypeId',
        fieldApiName: NOTE_TYPE_FIELD
    })
    wiredNoteTypeValues({ data, error }) {
        if (data) {
            this.noteTypeOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
            if (!this.noteTypeOptions.some(option => option.value === this.noteType)) {
                this.noteType = this.noteTypeOptions[0]?.value || '';
            }
        } else if (error) {
            this.noteTypeOptions = [];
            this.showToast(
                'Error',
                'Unable to load Note Type values.',
                'error'
            );
        }
    }

    @wire(getUserTagOptions)
    wiredUserTagOptions({ data, error }) {
        if (data) {
            this.userTagOptions = data.map(user => ({
                label: user.Name,
                value: user.Id
            }));
        } else if (error) {
            this.userTagOptions = [];
            console.log("Error in loading users: ", error);
        }
    }

    get defaultRecordTypeId() {
        return this.objectInfo?.data?.defaultRecordTypeId;
    }

    get isInternalNote() {
        return this.noteType === INTERNAL_NOTE;
    }

    get hasNotes() {
        return this.notes.length > 0;
    }

    renderedCallback() {
        if (this.recordId && this.initializedRecordId !== this.recordId) {
            this.initializedRecordId = this.recordId;
            this.loadInitialNotes();
        }

        this.setupNotesObserver();
    }

    disconnectedCallback() {
        this.notesObserver?.disconnect();
        this.notesObserver = null;
    }

    handleBodyChange(event) {
        this.body = event.detail.value;
    }

    handleNoteTypeChange(event) {
        this.noteType = event.detail.value;

        if (!this.isInternalNote) {
            this.userTagId = null;
        }
    }

    handleUserTagChange(event) {
        this.userTagId = event.detail.value;
    }

    async handleSubmit() {
        const bodyField = this.template.querySelector('lightning-textarea');
        bodyField?.reportValidity();

        if (!this.body || !this.body.trim()) {
            this.showToast('Error', 'Please enter note content before posting.', 'error');
            return;
        }

        if (!this.recordId) {
            this.showToast('Error', 'Unable to determine the related ticket.', 'error');
            return;
        }

        this.isSaving = true;
        try {
            await createSharedNote({
                ticketId: this.recordId,
                body: this.body,
                noteType: this.noteType,
            });

            this.showToast('Success', 'Note posted successfully.', 'success');
            this.body = '';

            await this.loadInitialNotes();
        } catch (error) {
            const message =
                (error && error.body && error.body.message) ||
                'An unexpected error occurred while posting the note.';
            this.showToast('Error', message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async loadInitialNotes() {
        if (!this.recordId) {
            return;
        }

        this.isLoadingNotes = true;
        this.isLoadingMore = false;
        this.hasMoreNotes = true;
        this.lastCreatedDate = null;
        this.lastNoteId = null;

        try {
            const records = await getSharedNotes({
                ticketId: this.recordId,
                pageSize: PAGE_SIZE,
                lastCreatedDate: null,
                lastNoteId: null
            });

            this.notes = this.decorateNotes(records || []);
            this.updatePaginationState(records || []);
        } catch (error) {
            this.notes = [];
            this.hasMoreNotes = false;

            const message =
                (error && error.body && error.body.message) ||
                'Unable to load shared notes.';
            this.showToast('Error', message, 'error');
        } finally {
            this.isLoadingNotes = false;
        }
    }

    async loadMoreNotes() {
        if (
            !this.recordId ||
            !this.hasMoreNotes ||
            this.isLoadingNotes ||
            this.isLoadingMore
        ) {
            return;
        }

        this.isLoadingMore = true;

        try {
            const records = await getSharedNotes({
                ticketId: this.recordId,
                pageSize: PAGE_SIZE,
                lastCreatedDate: this.lastCreatedDate,
                lastNoteId: this.lastNoteId
            });

            const nextNotes = this.decorateNotes(records || []);
            this.notes = [...this.notes, ...nextNotes];
            this.updatePaginationState(records || []);
        } catch (error) {
            const message =
                (error && error.body && error.body.message) ||
                'Unable to load more shared notes.';
            this.showToast('Error', message, 'error');
        } finally {
            this.isLoadingMore = false;
        }
    }

    updatePaginationState(records) {
        if (!records.length || records.length < PAGE_SIZE) {
            this.hasMoreNotes = false;
            return;
        }

        const lastRecord = records[records.length - 1];
        this.lastCreatedDate = lastRecord.CreatedDate;
        this.lastNoteId = lastRecord.Id;
    }

    decorateNotes(records) {
        return records.map(note => {
            const authorName = note.CreatedBy?.Name || 'Unknown User';

            return {
                ...note,
                body: note.Body__c || '',
                authorName,
                initials: this.getInitials(authorName),
                formattedDate: this.formatDate(note.CreatedDate)
            };
        });
    }

    getInitials(name) {
        const parts = (name || 'U').trim().split(/\s+/);

        if (parts.length === 1) {
            return parts[0].slice(0, 2).toUpperCase();
        }

        return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
    }

    formatDate(value) {
        if (!value) {
            return '';
        }

        return new Intl.DateTimeFormat(undefined, {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }).format(new Date(value));
    }

    handleNotesScroll(event) {
        const container = event.currentTarget;

        if (
            container.scrollTop + container.clientHeight >=
            container.scrollHeight - 80
        ) {
            this.loadMoreNotes();
        }
    }

    setupNotesObserver() {
        if (this.notesObserver || !this.hasMoreNotes || this.isLoadingNotes) {
            return;
        }

        const sentinel = this.template.querySelector('.notes-sentinel');

        if (!sentinel) {
            return;
        }

        this.notesObserver = new IntersectionObserver(
            entries => {
                if (entries.some(entry => entry.isIntersecting)) {
                    this.loadMoreNotes();
                }
            },
            {
                root: this.template.querySelector('.notes-container'),
                rootMargin: '0px 0px 120px 0px'
            }
        );

        this.notesObserver.observe(sentinel);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}