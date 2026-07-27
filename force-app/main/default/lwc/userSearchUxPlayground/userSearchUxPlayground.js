import { LightningElement, track } from 'lwc';

const MOCK_USERS = [
    { id: 1, name: 'Arjun Mehta', email: 'arjun.mehta@example.com', phone: '+91 98765 43210', dept: 'Engineering' },
    { id: 2, name: 'Priya Sharma', email: 'priya.s@example.com', phone: '+91 87654 32109', dept: 'Product' },
    { id: 3, name: 'Rohan Das', email: 'rohan.das@example.com', phone: '+91 76543 21098', dept: 'Design' },
    { id: 4, name: 'Ananya Iyer', email: 'ananya.i@example.com', phone: '+91 65432 10987', dept: 'Marketing' },
    { id: 5, name: 'Kabir Singh', email: 'kabir.s@example.com', phone: '+91 99887 76655', dept: 'Sales' },
    { id: 6, name: 'Meera Nair', email: 'meera.nair@example.com', phone: '+91 88776 65544', dept: 'Operations' },
    { id: 7, name: 'Vikram Malhotra', email: 'vikram.m@example.com', phone: '+91 77665 54433', dept: 'Finance' }
];

export default class UserSearchUxPlayground extends LightningElement {
    @track isFormModalOpen = false;
    @track isNestedModalOpen = false;
    @track activePattern = 'combobox';
    @track dealTitle = '';
    @track dealValue = '';
    @track selectedUser = null;
    @track searchQuery = '';
    @track isComboboxDropdownOpen = false;
    @track isAccordionOpen = false;
    @track slidingStep = 'form';
    @track actionLog = [];
    @track clickCount = 0;
    @track formMessage = '';

    get filteredUsers() {
        const query = (this.searchQuery || '').trim().toLowerCase();
        if (!query) {
            return MOCK_USERS;
        }

        return MOCK_USERS.filter((user) =>
            user.name.toLowerCase().includes(query) ||
            user.email.toLowerCase().includes(query) ||
            user.phone.includes(query) ||
            user.dept.toLowerCase().includes(query)
        );
    }

    get isNestedPattern() {
        return this.activePattern === 'nested';
    }

    get isComboboxPattern() {
        return this.activePattern === 'combobox';
    }

    get isSlidingPattern() {
        return this.activePattern === 'sliding';
    }

    get isAccordionPattern() {
        return this.activePattern === 'accordion';
    }

    get activeModeLabel() {
        return this.isNestedPattern ? 'Nested Mode' : 'Inline Mode';
    }

    get minimumSteps() {
        if (this.isNestedPattern) return '5';
        if (this.isComboboxPattern) return '3';
        return '4';
    }

    get cognitiveLoadLabel() {
        if (this.isNestedPattern) return 'Critical (9/10)';
        if (this.isComboboxPattern) return 'Very Low (2/10)';
        return 'Moderate (4/10)';
    }

    get selectedUserInitials() {
        if (!this.selectedUser?.name) return '';
        return this.selectedUser.name
            .split(' ')
            .map((part) => part[0])
            .join('');
    }

    get hasLogEntries() {
        return this.actionLog.length > 0;
    }

    get showSlidingSearchStep() {
        return this.isSlidingPattern && this.slidingStep === 'search';
    }

    setPattern(event) {
        const pattern =
            event?.target?.name ||
            event?.currentTarget?.name ||
            event?.currentTarget?.dataset?.pattern;
        if (!pattern || pattern === this.activePattern) {
            return;
        }

        this.activePattern = pattern;
        this.logAction(`Switched to ${pattern} pattern`, false);
        this.resetFormState();
    }

    handleOpenMainModal() {
        this.isFormModalOpen = true;
        this.formMessage = '';
        this.logAction('Opened main transaction modal');
    }

    handleCloseMainModal() {
        this.isFormModalOpen = false;
        this.logAction('Closed main modal');
        this.resetFormState();
    }

    handleDealTitleChange(event) {
        this.dealTitle = event.target.value;
    }

    handleDealValueChange(event) {
        this.dealValue = event.target.value;
    }

    handleSearchChange(event) {
        this.searchQuery = event.target.value || '';
        if (this.isComboboxPattern) {
            this.isComboboxDropdownOpen = true;
        }
    }

    toggleCombobox() {
        this.isComboboxDropdownOpen = !this.isComboboxDropdownOpen;
        this.logAction('Toggled combobox dropdown');
    }

    toggleAccordion() {
        this.isAccordionOpen = !this.isAccordionOpen;
        this.logAction('Toggled accordion panel');
    }

    openNestedModal() {
        this.isNestedModalOpen = true;
        this.logAction('Opened nested modal (anti-pattern)');
    }

    closeNestedModal() {
        this.isNestedModalOpen = false;
        this.logAction('Closed nested modal');
    }

    openSlidingSearch() {
        this.slidingStep = 'search';
        this.logAction('Opened sliding search panel');
    }

    backToFormFromSliding() {
        this.slidingStep = 'form';
        this.logAction('Returned to form view');
    }

    handleSelectUser(event) {
        const userId = Number(event.currentTarget.dataset.id);
        const selected = MOCK_USERS.find((user) => user.id === userId);
        if (!selected) {
            return;
        }

        this.selectedUser = selected;
        this.searchQuery = '';
        this.isComboboxDropdownOpen = false;
        this.isAccordionOpen = false;
        this.slidingStep = 'form';
        this.isNestedModalOpen = false;
        this.logAction(`Selected user: ${selected.name}`);
    }

    handleDeselectUser() {
        this.selectedUser = null;
        this.logAction('Removed selected contact');
    }

    handleSubmit() {
        if (!this.dealTitle) {
            this.formMessage = 'Validation failed: Deal title is required.';
            this.logAction('Validation failed: Title required', false);
            return;
        }

        this.formMessage = `Deal "${this.dealTitle}" created with ${this.selectedUser ? this.selectedUser.name : 'No Contact'}.`;
        this.logAction('Deal created successfully');
        window.setTimeout(() => {
            this.isFormModalOpen = false;
            this.resetFormState();
        }, 1200);
    }

    logAction(action, isClick = true) {
        if (isClick) {
            this.clickCount += 1;
        }

        const time = new Date().toLocaleTimeString([], {
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        });

        this.actionLog = [{ time, action }, ...this.actionLog.slice(0, 8)];
    }

    resetFormState() {
        this.dealTitle = '';
        this.dealValue = '';
        this.selectedUser = null;
        this.searchQuery = '';
        this.isComboboxDropdownOpen = false;
        this.isAccordionOpen = false;
        this.slidingStep = 'form';
        this.isNestedModalOpen = false;
        this.formMessage = '';
        this.clickCount = 0;
        this.actionLog = [];
    }
}