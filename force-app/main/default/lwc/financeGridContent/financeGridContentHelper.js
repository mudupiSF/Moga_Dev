const formulas = [
    {
        field: 'Income__c',
        dependencies: ['Revenue_from_operations__c', 'Other_Income__c'],
        calculate: (record) => {
            const revenue = parseFloat(record.Revenue_from_operations__c) || 0;
            const income = parseFloat(record.Other_Income__c) || 0;
            return revenue + income;
        }
    },
    {
        field: 'Expenses__c',
        dependencies: ['Cost_of_goods__c', 'Direct_Expenses__c', 'Employee_costs__c', 'Administration_Expenses__c', 'Selling_and_Distribution_Expenses__c', 'Financial_Expenses__c', 'Depreciation__c'],
        calculate: (record) => {
            const cog = parseFloat(record.Cost_of_goods__c) || 0;
            const directExpense = parseFloat(record.Direct_Expenses__c) || 0;
            const empCost = parseFloat(record.Employee_costs__c) || 0;
            const adminExpense = parseFloat(record.Administration_Expenses__c) || 0;
            const sellingExpense = parseFloat(record.Selling_and_Distribution_Expenses__c) || 0;
            const finExpense = parseFloat(record.Financial_Expenses__c) || 0;
            const depreciation = parseFloat(record.Depreciation__c) || 0;
            return cog + directExpense + empCost + adminExpense + sellingExpense + finExpense + depreciation;
        }
    },
    {
        field: 'Profit_before_tax__c',
        dependencies: ['Income__c', 'Expenses__c'],
        calculate: (record) => {
            const income = parseFloat(record.Income__c) || 0;
            const expenses = parseFloat(record.Expenses__c) || 0;
            return income - expenses;
        }
    },
    {
        field: 'Profit_after_tax__c',
        dependencies: ['Provision_for_tax__c', 'Profit_before_tax__c'],
        calculate: (record) => {
            const provision = parseFloat(record.Provision_for_tax__c) || 0;
            const pbt = parseFloat(record.Profit_before_tax__c) || 0;
            return pbt - provision;
        }
    },
    {
        field: 'Profit_available_for_equity_shareholders__c',
        dependencies: ['Profit_after_tax__c', 'Preference_dividend_including_tax__c'],
        calculate: (record) => {
            const dividend = parseFloat(record.Preference_dividend_including_tax__c) || 0;
            const pat = parseFloat(record.Profit_after_tax__c) || 0;
            return pat - dividend;
        }
    },
    {
        field: 'Cash_profit__c',
        dependencies: ['Profit_after_tax__c', 'Depreciation__c'],
        calculate: (record) => {
            const depreciation = parseFloat(record.Depreciation__c) || 0;
            const pat = parseFloat(record.Profit_after_tax__c) || 0;
            return pat + depreciation;
        }
    },
    {
        field: 'Liabilities_Total__c',
        dependencies: ['Equity_Capital__c', 'Share_Application_Money__c', 'Reserves_Surplus__c', 'Secured_loan__c', 'Secured_loans_OD_CC_Working_Capital__c', 'Unsecured_loans__c', 'Deffered_tax_liability__c', 'Other_long_term_liabilities__c', 'Current_Liabilities_and_Provision__c', 'Sundry_creditors__c', 'Other_current_liabilities_and_provisions__c'],
        calculate: (record) => {
            const equity = parseFloat(record.Equity_Capital__c) || 0;
            const sa = parseFloat(record.Share_Application_Money__c) || 0;
            const reserves = parseFloat(record.Reserves_Surplus__c) || 0;
            const sl = parseFloat(record.Secured_loan__c) || 0;
            const slwc = parseFloat(record.Secured_loans_OD_CC_Working_Capital__c) || 0;
            const ul = parseFloat(record.Unsecured_loans__c) || 0;
            const dtl = parseFloat(record.Deffered_tax_liability__c) || 0;
            const oll = parseFloat(record.Other_long_term_liabilities__c) || 0;
            const clp = parseFloat(record.Current_Liabilities_and_Provision__c) || 0;
            const sundry = parseFloat(record.Sundry_creditors__c) || 0;
            const oclap = parseFloat(record.Other_current_liabilities_and_provisions__c) || 0;
            return equity + sa + reserves + sl + slwc + ul + dtl + oclap + oll + clp + sundry;
        }
    },
    {
        field: 'Assets_Total__c',
        dependencies: ['Fixed_Assets__c', 'Capital_WIP__c', 'Investments__c', 'Long_term_loans_and_advances__c', 'other_non_current_assets__c', 'Current_assets__c', 'Sundry_debtors__c', 'Closing_stock__c', 'Cash_and_bank_balances__c', 'Other_current_assets__c'],
        calculate: (record) => {
            const fixed = parseFloat(record.Fixed_Assets__c) || 0;
            const wip = parseFloat(record.Capital_WIP__c) || 0;
            const investment = parseFloat(record.Investments__c) || 0;
            const loans = parseFloat(record.Long_term_loans_and_advances__c) || 0;
            const ocna = parseFloat(record.other_non_current_assets__c) || 0;
            const current = parseFloat(record.Current_assets__c) || 0;
            const sundry = parseFloat(record.Sundry_debtors__c) || 0;
            const cs = parseFloat(record.Closing_stock__c) || 0;
            const cb = parseFloat(record.Cash_and_bank_balances__c) || 0;
            const ocna2 = parseFloat(record.Other_current_assets__c) || 0;
            return fixed + wip + investment + loans + ocna + current + sundry + cs + cb + ocna2;
        }
    },
    {
        field: 'Return_on_Capital_Employed__c',
        dependencies: ['Profit_before_tax__c', 'Financial_Expenses__c', 'Equity_Capital__c', 'Share_Application_Money__c', 'Reserves_Surplus__c', 'Secured_loan__c', 'Unsecured_loans__c'],
        calculate: (record) => {
            const pbt = parseFloat(record.Profit_before_tax__c) || 0;
            const fe = parseFloat(record.Financial_Expenses__c) || 0;
            const equity = parseFloat(record.Equity_Capital__c) || 0;
            const sa = parseFloat(record.Share_Application_Money__c) || 0;
            const reserves = parseFloat(record.Reserves_Surplus__c) || 0;
            const sl = parseFloat(record.Secured_loan__c) || 0;
            const ul = parseFloat(record.Unsecured_loans__c) || 0;
            return (pbt + fe) / (equity + sa + reserves + sl + ul);
        }
    },
    {
        field: 'PAT_Income__c',
        dependencies: ['Income__c', 'Profit_after_tax__c'],
        calculate: (record) => {
            const pat = parseFloat(record.Profit_after_tax__c) || 0;
            const income = parseFloat(record.Income__c) || 0;
            return (pat / income) * 100 + '%';
        }
    },
    {
        field: 'PAT_Assets_employed__c',
        dependencies: ['Assets_Total__c', 'Profit_after_tax__c'],
        calculate: (record) => {
            const pat = parseFloat(record.Profit_after_tax__c) || 0;
            const assets = parseFloat(record.Assets_Total__c) || 0;
            return (pat / assets) * 100 + '%';
        }
    },
    {
        field: 'Interest_Coverage__c',
        dependencies: ['Profit_before_tax__c', 'Financial_Expenses__c'],
        calculate: (record) => {
            const pbt = parseFloat(record.Profit_before_tax__c) || 0;
            const fe = parseFloat(record.Financial_Expenses__c) || 0;
            return (pbt + fe) / (fe);
        }
    },
    {
        field: 'Debt_Ratio__c',
        dependencies: ['Secured_loan__c', 'Secured_loans_OD_CC_Working_Capital__c', 'Unsecured_loans__c', 'Liabilities_Total__c'],
        calculate: (record) => {
            const sl = parseFloat(record.Secured_loan__c) || 0;
            const slwc = parseFloat(record.Secured_loans_OD_CC_Working_Capital__c) || 0;
            const ul = parseFloat(record.Unsecured_loans__c) || 0;
            const liabilities = parseFloat(record.Liabilities_Total__c) || 0;
            return (sl + slwc + ul) / liabilities;
        }
    },
    {
        field: 'Current_Ratio__c',
        dependencies: ['Sundry_debtors__c', 'Closing_stock__c', 'Cash_and_bank_balances__c', 'Other_current_assets__c', 'Sundry_creditors__c', 'Other_current_liabilities_and_provisions__c', 'Secured_loans_OD_CC_Working_Capital__c'],
        calculate: (record) => {
            const sundtryDebt = parseFloat(record.Sundry_debtors__c) || 0;
            const cs = parseFloat(record.Closing_stock__c) || 0;
            const cb = parseFloat(record.Cash_and_bank_balances__c) || 0;
            const ocna = parseFloat(record.Other_current_assets__c) || 0;
            const oclap = parseFloat(record.Other_current_liabilities_and_provisions__c) || 0;
            const slwc = parseFloat(record.Secured_loans_OD_CC_Working_Capital__c) || 0;
            const sundrycred = parseFloat(record.Sundry_creditors__c) || 0;
            return (sundtryDebt + cs + cb + ocna) / (oclap + slwc + sundrycred);
        }
    },
    {
        field: 'Quick_Asset_Ratio__c',
        dependencies: ['Sundry_debtors__c', 'Cash_and_bank_balances__c', 'Other_current_assets__c', 'Sundry_creditors__c', 'Other_current_liabilities_and_provisions__c'],
        calculate: (record) => {
            const sundtryDebt = parseFloat(record.Sundry_debtors__c) || 0;
            const cb = parseFloat(record.Cash_and_bank_balances__c) || 0;
            const ocna = parseFloat(record.Other_current_assets__c) || 0;
            const oclap = parseFloat(record.Other_current_liabilities_and_provisions__c) || 0;
            const sundrycred = parseFloat(record.Sundry_creditors__c) || 0;
            return (sundtryDebt + cb + ocna) / (oclap + sundrycred);
        }
    },
    {
        field: 'Cash_Ratio__c',
        dependencies: ['Cash_and_bank_balances__c', 'Sundry_creditors__c', 'Other_current_liabilities_and_provisions__c'],
        calculate: (record) => {
            const cb = parseFloat(record.Cash_and_bank_balances__c) || 0;
            const oclap = parseFloat(record.Other_current_liabilities_and_provisions__c) || 0;
            const sundrycred = parseFloat(record.Sundry_creditors__c) || 0;
            return cb / (oclap + sundrycred);
        }
    },
    {
        field: 'TOL_TNW__c',
        dependencies: ['Secured_loan__c', 'Secured_loans_OD_CC_Working_Capital__c', 'Unsecured_loans__c', 'Deffered_tax_liability__c', 'Other_long_term_liabilities__c', 'Sundry_creditors__c', 'Other_current_liabilities_and_provisions__c', 'Equity_Capital__c', 'Share_Application_Money__c', 'Reserves_Surplus__c'],
        calculate: (record) => {
            const sl = parseFloat(record.Secured_loan__c) || 0;
            const slwc = parseFloat(record.Secured_loans_OD_CC_Working_Capital__c) || 0;
            const ul = parseFloat(record.Unsecured_loans__c) || 0;
            const dtl = parseFloat(record.Deffered_tax_liability__c) || 0;
            const oclap = parseFloat(record.Other_current_liabilities_and_provisions__c) || 0;
            const oll = parseFloat(record.Other_long_term_liabilities__c) || 0;
            const sundrycred = parseFloat(record.Sundry_creditors__c) || 0;
            const ec = parseFloat(record.Equity_Capital__c) || 0;
            const sa = parseFloat(record.Share_Application_Money__c) || 0;
            const reserves = parseFloat(record.Reserves_Surplus__c) || 0;
            return (sl + slwc + ul + dtl + oclap + oll + sundrycred) / (ec + sa + reserves);
        }
    },
    {
        field: 'DSCR__c',
        dependencies: ['Financial_Expenses__c', 'Depreciation__c', 'Profit_after_tax__c', 'Secured_loan__c'],
        calculate: (record) => {
            const fe = parseFloat(record.Financial_Expenses__c) || 0;
            const dep = parseFloat(record.Depreciation__c) || 0;
            const pat = parseFloat(record.Profit_after_tax__c) || 0;
            const sl = parseFloat(record.Secured_loan__c) || 0;
            return (pat + fe + dep) / ((fe + sl) / 5);
        }
    },
    {
        field: 'Debtors_TO__c',
        dependencies: ['Sundry_debtors__c', 'Revenue_from_operations__c'],
        calculate: (record) => {
            const sundrydebt = parseFloat(record.Sundry_debtors__c) || 0;
            const revenue = parseFloat(record.Revenue_from_operations__c) || 0;
            return (sundrydebt / revenue) * 100;
        }
    },
    {
        field: 'Debtors_TO_Ratio__c',
        dependencies: ['Sundry_debtors__c', 'Revenue_from_operations__c'],
        calculate: (record) => {
            const sundrydebt = parseFloat(record.Sundry_debtors__c) || 0;
            const revenue = parseFloat(record.Revenue_from_operations__c) || 0;
            return sundrydebt / revenue;
        }
    },
    {
        field: 'Debtor_days__c',
        dependencies: ['Debtors_TO_Ratio__c'],
        calculate: (record) => {
            const debtRatio = parseFloat(record.Debtors_TO_Ratio__c) || 0;
            return 365 / debtRatio;
        }
    }
];

export default formulas;