import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';

export default class CustomLogoutScreen extends LightningElement {


    get siteHost() {
        return 'auth.new.firstlegal.com';
        //return window.location.hostname;
    }

    handleSignOut() {
        // Standard Experience Cloud logout endpoint - clears the session
        window.location.href = '/secur/logout.jsp';
    }

    handleStaySignedIn() {
        // Send them back to the site home page
        window.location.href = '/support';
        // this[NavigationMixin.Navigate]({
        //     type: 'comm__namedPage',
        //     attributes: {
        //         name: 'Home'
        //     }
        // });

        // Fallback in case the named page nav doesn't resolve in your template:
        // window.location.href = basePath;
    }
}