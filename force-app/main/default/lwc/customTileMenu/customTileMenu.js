import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import KNOWLEDGE_BASE_ICON from '@salesforce/resourceUrl/iconKnowledgeBase';
import CREATE_TICKET_ICON from '@salesforce/resourceUrl/iconCreateTicket';
import CONTACT_SUPPORT_ICON from '@salesforce/resourceUrl/iconContactSupport';

export default class CustomTileMenu extends NavigationMixin(LightningElement) {
    // Tile 1
    @api icon1 = KNOWLEDGE_BASE_ICON;
    @api url1 = '/support/knowledge-base';
    @api openInNewTab1 = false;

    // Tile 2
    @api icon2 = CREATE_TICKET_ICON;
    @api url2 = '/support/ticketsubmission';
    @api openInNewTab2 = false;

    // Tile 3
    @api icon3 = CONTACT_SUPPORT_ICON;
    @api url3 = '/support/contactus';
    @api openInNewTab3 = false;

    get tiles() {
        return [
            {
                key: 'tile-1',
                icon: this.icon1,
                url: this.url1,
                target: this.openInNewTab1 ? '_blank' : '_self'
            },
            {
                key: 'tile-2',
                icon: this.icon2,
                url: this.url2,
                target: this.openInNewTab2 ? '_blank' : '_self'
            },
            {
                key: 'tile-3',
                icon: this.icon3,
                url: this.url3,
                target: this.openInNewTab3 ? '_blank' : '_self'
            }
        ];
    }

    handleTileClick(event) {
    const url = event.currentTarget.dataset.url;
    const target = event.currentTarget.dataset.target;

    if (!url) {
        return;
    }

    if (target === '_blank') {
        window.open(url, '_blank');
    } else {
        window.location.href = url;
    }
}
}