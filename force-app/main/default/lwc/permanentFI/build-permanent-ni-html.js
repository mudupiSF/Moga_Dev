/* One-off script to merge Office FI NI template into permanentFI.html */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname);
const office = fs.readFileSync(path.join(root, '..', 'officeFI', 'officeFI.html'), 'utf8');
const start = office.indexOf('<template lwc:if={isNonIndividual}>');
const end = office.indexOf('</template>\n                <template lwc:else>', start);
let ni = office.slice(start, end + '</template>'.length);
ni = ni
  .replace(/Office residence FI/g, 'Permanent residence FI')
  .replace(/aria-label="Business office address"/g, 'aria-label="Residence address"')
  .replace(/Business \/ office address/g, 'Residence address')
  .replace(/form-info-label">Resi cum off/g, 'form-info-label">Residential cum office')
  .replace(/form-field-label">Resi cum off/g, 'form-field-label">Residential cum office')
  .replace(/label="Resi cum off"/g, 'label="Residential cum office"');

const obsLoan = fs.readFileSync(path.join(root, '_niObservationLoan.html'), 'utf8');
ni = ni.replace(
  '</section>\n\n                <section class="form-card" aria-label="FI feedback">',
  `</section>\n\n${obsLoan}\n                <section class="form-card" aria-label="FI feedback">`
);

const perm = fs.readFileSync(path.join(root, 'permanentFI.html'), 'utf8');
const bodyStart = perm.indexOf('<div class="form-body">');
const bodyInnerStart = perm.indexOf('>', bodyStart) + 1;
const footerStart = perm.indexOf('            </div>\n        </div>\n\n        <template lwc:if={uiFlags.showFooter}>');
const individual = perm.slice(bodyInnerStart, footerStart).trim();
const header = perm.slice(0, bodyInnerStart);
const footer = perm.slice(footerStart);
const subtitleFix = header.replace(
  '<p class="form-header-subtitle">Field investigation — permanent residence</p>',
  '<p class="form-header-subtitle">{headerSubtitle}</p>'
);
const merged = `${subtitleFix}
                ${ni}
                <template lwc:else>
${individual}
                </template>
${footer}`;
fs.writeFileSync(path.join(root, 'permanentFI.html'), merged);
console.log('permanentFI.html updated');