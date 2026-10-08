import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import userId from '@salesforce/user/Id';
import basePath from '@salesforce/community/basePath';
import { refreshApex } from '@salesforce/apex';

import getNotifications from '@salesforce/apex/NotificationController.getNotifications';
import markAsRead from '@salesforce/apex/NotificationController.markAsRead';
import markAllAsReadApex from '@salesforce/apex/NotificationController.markAllAsRead';

export default class Profilemenu extends NavigationMixin(LightningElement) {
    showNotifications = false;
    showProfileMenu = false;
    showLogoutConfirm = false;
    _notifications = [];
    _wiredNotificationsResult;

    // Getters and hooks
    get loginPageUrl() {
        return window.location.origin + basePath + '/login';
    }

    get logoutUrl() {
        const sitePrefix = basePath.replace(/\/s$/i, '').replace(/\/$/, '');
        return `${sitePrefix}/secur/logout.jsp`;
    }

    get isLoggedIn() {
        return !!userId;
    }

    get profileUrl() {
        return `/support/profile/${userId}`;
    }

    // get siteHost() {
    //     return window.location.host;
    // }

    @wire(getNotifications)
    wiredNotifications(result) {
        this._wiredNotificationsResult = result;
        if (result.data) {
            this._notifications = result.data;
        } else if (result.error) {
            console.error('Error loading notifications:', result.error);
        }
    }

    @api
    get notifications() {
        return this._notifications;
    }
    set notifications(value) {
        this._notifications = value || [];
    }

    get unreadCount() {
        return this._notifications.filter((n) => n.unread).length;
    }

    get hasUnread() {
        return this.unreadCount > 0;
    }

    connectedCallback() {
        this._handleOutsideClick = this.handleOutsideClick.bind(this);
    }

    renderedCallback() {
        if (this.showNotifications || this.showProfileMenu) {
            document.addEventListener('click', this._handleOutsideClick, true);
        } else {
            document.removeEventListener('click', this._handleOutsideClick, true);
        }
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._handleOutsideClick, true);
    }

    // Helper functions for the profile menu as a whole
    handleOutsideClick(event) {
        if (!this.template.contains(event.target)) {
            this.showNotifications = false;
            this.showProfileMenu = false;
        }
    }

    toggleNotifications(event) {
        event.stopPropagation();
        this.showNotifications = !this.showNotifications;
        this.showProfileMenu = false;
    }

    toggleProfileMenu(event) {
        event.stopPropagation();
        this.showProfileMenu = !this.showProfileMenu;
        this.showNotifications = false;
    }

    // Helper functions for notifications

    refreshNotifications() {
        if (this._wiredNotificationsResult) {
            refreshApex(this._wiredNotificationsResult);
        }
    }

    handleMarkAllRead(event) {
        event.stopPropagation();
        markAllAsReadApex()
            .then(() => this.refreshNotifications())
            .catch((error) => {
                console.error('Error marking all notifications as read:', error);
            });
    }

    handleNotificationClick(event) {
        const notificationId = event.currentTarget.dataset.id;
        const ticketId = event.currentTarget.dataset.ticketId;

        markAsRead({ notificationId })
            .then(() => this.refreshNotifications())
            .catch((error) => {
                console.error('Error marking notification as read:', error);
            });

        if (ticketId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: ticketId,
                    objectApiName: 'Case',
                    actionName: 'view'
                }
            });
        }
    }

    // Helper functions for logout
    stopPropagation(event) {
        event.stopPropagation();
    }

    handleLogoutClick(event) {
        event.preventDefault();
        event.stopPropagation();
        this.showProfileMenu = false;
        this.showLogoutConfirm = true;
    }

    handleCancelLogout(event) {
        if (event) {
            event.stopPropagation();
        }
        this.showLogoutConfirm = false;
    }

    async handleConfirmLogout(event) {
        event.stopPropagation();
        this.showLogoutConfirm = false;
        try {
            await fetch(this.logoutUrl, {
                method: 'GET',
                credentials: 'same-origin',
                redirect: 'follow'
            });
        } catch (error) {
            console.error('Logout request failed:', error);
        } finally {
            window.location.href = this.loginPageUrl;
        }
    }

    handleProfileClick(event){
    event.preventDefault();
    this[NavigationMixin.Navigate]({
        type: 'comm__namedPage',
        attributes: {
            name: 'Profile_Detail__c'
        }
    });
    }
}