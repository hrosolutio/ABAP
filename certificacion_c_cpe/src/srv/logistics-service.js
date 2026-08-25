const cds = require('@sap/cds');

const RATE_BY_MODE = { A: 15, S: 5, R: 8 };

module.exports = cds.service.impl(async function () {
  const { Shipments, Packages } = this.entities;

  this.after('READ', Shipments, async (results, req) => {
    const shipments = Array.isArray(results) ? results : [results];
    if (!shipments.length) return;

    for (const shipment of shipments) {
      let packages = shipment.packages;

      // Hint: packages might not be expanded in the initial request.
      if (!packages) {
        packages = await SELECT.from(Packages).where({ parent_ID: shipment.ID });
      }

      const totalWeight = (packages || []).reduce(
        (sum, pkg) => sum + (pkg.weight || 0),
        0
      );

      shipment.totalWeight = totalWeight;
      shipment.shippingFee = totalWeight * (RATE_BY_MODE[shipment.mode] || 0);
    }
  });
});
