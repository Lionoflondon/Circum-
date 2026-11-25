"use strict";

// Confirmed by the business owner on 15 October 2026. Snapshot each new invoice;
// later registration changes must not rewrite historical supplier/tax records.
function businessInvoiceIdentity() {
  return {
    supplier: {
      legalName: "Circum Technologies Ltd",
      tradingName: "Circum",
      companyNumber: "13931698",
      registeredAddress: "124 City Road, London, England EC1V 2NX",
      vatRegistrationStatus: "not_registered",
      vatRegistrationNumber: null,
    },
    tax: {treatment: "not_vat_registered", vatAmount: 0, currency: "GBP"},
  };
}
module.exports = {businessInvoiceIdentity};
