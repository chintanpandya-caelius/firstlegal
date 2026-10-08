import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import CASE_OBJECT from '@salesforce/schema/Case';
import getCurrentUserEmail from '@salesforce/apex/TicketController.getCurrentUserEmail';
import createDraftTicket from '@salesforce/apex/TicketController.createDraftTicket';
import submitTicketApex from '@salesforce/apex/TicketController.submitTicket';
import deleteDraftTicket from '@salesforce/apex/TicketController.deleteDraftTicket';


const TYPE_API_NAME = 'Type';
const SUBTYPE_API_NAME = 'Ticket_SubType__c';

const PRIORITY_OPTIONS = [
    { label: 'Low', value: 'Low' },
    { label: 'Standard', value: 'Standard' },
    { label: 'High', value: 'High' },
    { label: 'Urgent', value: 'Urgent' }
];

export default class SubmitTicket extends LightningElement {
    userEmail = '';
    draftRecordId;
    recordTypeId;

    ticketType = '';
    subType = '';
    priority = 'Standard';
    subject = '';
    description = '';
    matterNumber = '';
    caseNumber = '';

    uploadedFileNames = [];
    isSubmitting = false;

    // Success banner state
    showSuccessBanner = false;
    successMessage = '';

    acceptedFormats = ['.pdf', '.docx', '.png', '.jpg', '.jpeg'];

    priorityOptions = PRIORITY_OPTIONS;


    typeOptions = [];
    subtypeMeta;
    isPicklistLoading = true;

    @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
    wiredObjectInfo({ data, error }) {
        if (data) {
            this.recordTypeId = data.defaultRecordTypeId;
        } else if (error) {
            
            console.error('Could not load Case object info', error);
        }
    }

    @wire(getPicklistValuesByRecordType, {
        objectApiName: CASE_OBJECT,
        recordTypeId: '$recordTypeId'
    })
    wiredPicklistValues({ data, error }) {
        if (data) {
            const typeField = data.picklistFieldValues[TYPE_API_NAME];
            const subtypeField = data.picklistFieldValues[SUBTYPE_API_NAME];

            this.typeOptions = typeField
                ? typeField.values.map((v) => ({ label: v.label, value: v.value }))
                : [];
            this.subtypeMeta = subtypeField;
            this.isPicklistLoading = false;
        } else if (error) {
       
            console.error('Could not load Type / Sub-Type picklist values', error);
            this.isPicklistLoading = false;
        }
    }

    get subTypeOptions() {
        if (!this.ticketType || !this.subtypeMeta) {
            return [];
        }
        const controllingIndex = this.subtypeMeta.controllerValues[this.ticketType];
        if (controllingIndex === undefined) {
            return [];
        }
        return this.subtypeMeta.values
            .filter((entry) => entry.validFor.includes(controllingIndex))
            .map((entry) => ({ label: entry.label, value: entry.value }));
    }

    get isSubTypeDisabled() {
        return !this.ticketType || this.isPicklistLoading;
    }

    get subTypePlaceholder() {
        if (this.isPicklistLoading) {
            return 'Loading...';
        }
        return this.ticketType ? '--None--' : 'Select a Ticket Type first';
    }

    get isNewTicket() {
        return !this.draftRecordId;
    }

    connectedCallback() {
        // Pre-fill signed-in user's email.
        getCurrentUserEmail()
            .then((email) => {
                this.userEmail = email;
            })
            .catch(() => {
                this.userEmail = '';
            });

        
        createDraftTicket({ contactEmail: this.userEmail })
            .then((recordId) => {
                this.draftRecordId = recordId;
            })
            .catch((error) => {
                
                console.error('Could not create draft ticket', error);
            });
    }

    handleTicketTypeChange(event) {
        this.ticketType = event.detail.value;
        this.subType = '';
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.detail.value;
    }

    handleUploadFinished(event) {
        const files = event.detail.files || [];
        this.uploadedFileNames = [
            ...this.uploadedFileNames,
            ...files.map((f) => f.name)
        ];
    }

    validateFields() {
        const requiredEls = this.template.querySelectorAll(
            'lightning-input[required], lightning-combobox[required], lightning-textarea[required]'
        );
        let allValid = true;
        requiredEls.forEach((el) => {
            if (!el.reportValidity()) {
                allValid = false;
            }
        });
        return allValid;
    }

    handleSubmit() {
        if (!this.validateFields()) {
            this.showToast('Error', 'Please fill in all required fields.', 'error');
            return;
        }

        this.isSubmitting = true;
        this.showSuccessBanner = false;

        submitTicketApex({
            recordId: this.draftRecordId,
            contactEmail: this.userEmail,
            ticketType: this.ticketType,
            subType: this.subType,
            priority: this.priority,
            subject: this.subject,
            description: this.description,
            matterNumber: this.matterNumber,
            caseNumber: this.caseNumber
        })
            .then((ticketNumber) => {
                this.successMessage = `Ticket ${ticketNumber} has been submitted. We'll route it to the right team.`;
                this.showSuccessBanner = true;

                this.showToast(
                    'Ticket submitted',
                    `Your ticket ${ticketNumber} has been created. We'll route it to the right team.`,
                    'success'
                );

                this.resetForm();

                // Scroll the banner into view so the confirmation is impossible to miss
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    const banner = this.template.querySelector('.slds-scoped-notification');
                    if (banner) {
                        banner.scrollIntoView({ behavior: 'smooth', block: 'start' });
                    }
                }, 0);
            })
            .catch((error) => {
                this.showToast(
                    'Error submitting ticket',
                    this.extractErrorMessage(error),
                    'error'
                );
            })
            .finally(() => {
                this.isSubmitting = false;
            });
    }

    handleDismissBanner() {
        this.showSuccessBanner = false;
    }

    handleCancel() {
        if (this.draftRecordId) {
            deleteDraftTicket({ recordId: this.draftRecordId }).catch(() => {
              
            });
        }
        this.resetForm();
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    resetForm() {
        this.ticketType = '';
        this.subType = '';
        this.priority = 'Standard';
        this.subject = '';
        this.description = '';
        this.matterNumber = '';
        this.caseNumber = '';
        this.uploadedFileNames = [];
        this.draftRecordId = undefined;

        this.template
            .querySelectorAll('lightning-input, lightning-textarea, lightning-combobox')
            .forEach((el) => {
                if (typeof el.setCustomValidity === 'function') {
                    el.setCustomValidity('');
                    el.reportValidity();
                }
            });

        
        createDraftTicket({ contactEmail: this.userEmail })
            .then((recordId) => {
                this.draftRecordId = recordId;
            })
            .catch(() => {
                /* attachments unavailable until next submit */
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractErrorMessage(error) {
        if (error && error.body) {
            if (Array.isArray(error.body)) {
                return error.body.map((e) => e.message).join(', ');
            }
            if (error.body.message) {
                return error.body.message;
            }
        }
        return 'An unknown error occurred. Please try again.';
    }
}