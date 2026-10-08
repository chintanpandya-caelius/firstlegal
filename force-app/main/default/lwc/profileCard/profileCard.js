import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';

import USER_ID from '@salesforce/user/Id';

import NAME_FIELD from '@salesforce/schema/User.Name';
import FIRSTNAME_FIELD from '@salesforce/schema/User.FirstName';
import LASTNAME_FIELD from '@salesforce/schema/User.LastName';
import COMPANYNAME_FIELD from '@salesforce/schema/User.CompanyName';
import EMAIL_FIELD from '@salesforce/schema/User.Email';
import PHONE_FIELD from '@salesforce/schema/User.Phone';
import MOBILEPHONE_FIELD from '@salesforce/schema/User.MobilePhone';
import ABOUTME_FIELD from '@salesforce/schema/User.AboutMe';
import FULLPHOTOURL_FIELD from '@salesforce/schema/User.FullPhotoUrl';

import updateUserPhoto from '@salesforce/apex/ProfileCardController.updateUserPhoto';

export default class ProfileCard extends LightningElement {
    // Running user's record Id, resolved client-side - no Apex required.
    userId = USER_ID;
    objectApiName = 'User';
    isLoading = false;

    profilePhotoUrl;
    photoPreviewUrl;

    isPhotoModalOpen = false;
    selectedPhotoFile = null;
    selectedPhotoBase64 = null;

    wiredUserResult;

    // Field references (exposed to the template)
    nameField = NAME_FIELD;
    firstNameField = FIRSTNAME_FIELD;
    lastNameField = LASTNAME_FIELD;
    companyNameField = COMPANYNAME_FIELD;
    emailField = EMAIL_FIELD;
    phoneField = PHONE_FIELD;
    mobilePhoneField = MOBILEPHONE_FIELD;
    aboutMeField = ABOUTME_FIELD;

    // Per-field edit state
    isEditingName = false;
    isEditingCompany = false;
    isEditingPhone = false;
    isEditingMobile = false;
    isEditingAboutMe = false;

    @wire(getRecord, {
        recordId: '$userId',
        fields: [FULLPHOTOURL_FIELD]
    })
    wiredUser(result) {
        this.wiredUserResult = result;

        const { error, data } = result;

        if (data) {
            this.profilePhotoUrl = getFieldValue(
                data,
                FULLPHOTOURL_FIELD
            );
        } else if (error) {
            console.error('Error loading user profile:', error);
        }
    }

    get isAnyFieldEditing() {
        return (
            this.isEditingName ||
            this.isEditingCompany ||
            this.isEditingPhone ||
            this.isEditingMobile ||
            this.isEditingAboutMe
        );
    }

    handleCancel() {
        // Destroys the input-field(s) and swaps back to output-field, discarding any unsaved edits.
        this.isEditingName = false;
        this.isEditingCompany = false;
        this.isEditingPhone = false;
        this.isEditingMobile = false;
        this.isEditingAboutMe = false;
    }

    handleEdit(event) {
        const field = event.currentTarget.dataset.field;
        switch (field) {
            case 'Name':
                this.isEditingName = true;
                break;
            case 'Company':
                this.isEditingCompany = true;
                break;
            case 'Phone':
                this.isEditingPhone = true;
                break;
            case 'Mobile':
                this.isEditingMobile = true;
                break;
            case 'AboutMe':
                this.isEditingAboutMe = true;
                break;
            default:
                break;
        }
    }

    handleSuccess() {
        // Collapse every field back to display mode after a successful save.
        this.isEditingName = false;
        this.isEditingCompany = false;
        this.isEditingPhone = false;
        this.isEditingMobile = false;
        this.isEditingAboutMe = false;

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Your profile has been updated.',
                variant: 'success'
            })
        );
    }

    handleError(event) {
        const message =
            event?.detail?.detail ||
            event?.detail?.message ||
            'An error occurred while saving your profile. Please try again.';

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error updating profile',
                message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }

    openPhotoModal() {
    this.isPhotoModalOpen = true;

    this.photoPreviewUrl = this.profilePhotoUrl;
    this.selectedPhotoFile = null;
    this.selectedPhotoBase64 = null;
    }

    closePhotoModal() {
    this.isPhotoModalOpen = false;

    this.selectedPhotoFile = null;
    this.selectedPhotoBase64 = null;
    this.photoPreviewUrl = this.profilePhotoUrl;
    }

    triggerPhotoUpload() {
    const input = this.template.querySelector('.photo-file-input');

    if (input) {
        input.click();
    }
    }

    handlePhotoSelected(event) {
    const file = event.target.files[0];

    if (!file) {
        return;
    }

    const allowedTypes = [
        'image/jpeg',
        'image/jpg',
        'image/gif',
        'image/png'
    ];

    if (!allowedTypes.includes(file.type)) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Invalid file',
                message: 'Please select a JPG, GIF, or PNG image.',
                variant: 'error'
            })
        );

        event.target.value = '';
        return;
    }

    const maxSize = 16 * 1024 * 1024;

    if (file.size > maxSize) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'File too large',
                message: 'The maximum file size is 16 MB.',
                variant: 'error'
            })
        );

        event.target.value = '';
        return;
    }

    this.selectedPhotoFile = file;

    const reader = new FileReader();

    reader.onload = () => {
        this.selectedPhotoBase64 = reader.result.split(',')[1];

        /*
         * Immediately show the selected image in the modal.
         */
        this.photoPreviewUrl = reader.result;
    };

    reader.onerror = () => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Unable to read the selected image.',
                    variant: 'error'
                })
            );
        };

        reader.readAsDataURL(file);

        event.target.value = '';
    }

    get isPhotoSaveDisabled() {
        return !this.selectedPhotoBase64;
    }

    async savePhoto() {
        if (!this.selectedPhotoBase64) {
            return;
        }

        this.isLoading = true;

        try {
            await updateUserPhoto({
                base64Image: this.selectedPhotoBase64,
                fileName: this.selectedPhotoFile?.name,
                contentType: this.selectedPhotoFile?.type
            });

            await refreshApex(this.wiredUserResult);

            this.isPhotoModalOpen = false;

            this.selectedPhotoFile = null;
            this.selectedPhotoBase64 = null;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Your profile photo has been updated.',
                    variant: 'success'
                })
            );

        } catch (error) {
            console.error('Error updating profile photo:', error);

            const message =
                error?.body?.message ||
                'Unable to update your profile photo. Please try again.';

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error updating photo',
                    message,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }
}