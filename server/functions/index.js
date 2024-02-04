/* eslint-disable max-len */
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const functions = require("firebase-functions");
const stripe = require("stripe")(functions.config().stripe.testkey);

initializeApp();

const generateResponse = function(intent) {
  // Generate a response based on the intent's status
  switch (intent.status) {
    case "requires_action":
      // Card requires authentication
      return {
        clientSecret: intent.client_secret,
        requiresAction: true,
        status: intent.status,
      };
    case "requires_payment_method":
      // Card was not properly authenticated, suggest a new payment method
      return {
        error: "Your card was denied, please provide a new payment method",
      };
    case "succeeded":
      // Payment is complete, authentication not required
      // To cancel the payment after capture you will need to issue a Refund (https://stripe.com/docs/api/refunds).
      console.log("💰 Payment received!");
      return {clientSecret: intent.client_secret, status: intent.status};
  }
  return {
    error: "Failed",
  };
};


exports.StripePayEndpointMethodId = functions.https.onRequest(async (req, res) => {
  const {
    paymentMethodId,
    amount,
    currency,
    useStripeSdk,
  } = req.body;

  //   const orderAmount = calculateOrderAmount(items);
  const orderAmount = amount;

  try {
    if (paymentMethodId) {
      // Create new PaymentIntent with a PaymentMethod ID from the client.
      // confirmation_method: "manual",
      const params = {
        amount: orderAmount,
        confirm: true,
        currency,
        automatic_payment_methods: {
          enabled: true,
          allow_redirects: "never",
        },
        payment_method: paymentMethodId,
        use_stripe_sdk: useStripeSdk,
      };
      const intent = await stripe.paymentIntents.create(params);
      // After create, if the PaymentIntent's status is succeeded, fulfill the order.
      console.log(`Intent: ${intent}`);
      return res.send(generateResponse(intent));
    }
    return res.sendStatus(400);
  } catch (e) {
    // Handle "hard declines" e.g. insufficient funds, expired card, etc
    // See https://stripe.com/docs/declines/codes for more.
    return res.send({error: e.message});
  }
});

exports.StripePayEndpointIntentId = functions.https.onRequest(async (req, res) => {
  const {
    paymentIntentId,
  } = req.body;

  try {
    if (paymentIntentId) {
      // Confirm the PaymentIntent to finalize payment after handling a required action
      // on the client.
      const intent = await stripe.paymentIntents.confirm(paymentIntentId);
      // After confirm, if the PaymentIntent's status is succeeded, fulfill the order.
      return res.send(generateResponse(intent));
    } return res.sendStatus(400);
  } catch (e) {
    // Handle "hard declines" e.g. insufficient funds, expired card, etc
    // See https://stripe.com/docs/declines/codes for more.
    return res.send({error: e.message});
  }
});


exports.calculateEarnings = functions.https.onRequest(async (req, res) => {
  try {
    const {riderId} = req.body;

    // Retrieve the 'history' database reference
    const historyRef = getFirestore().collection("history");

    // Query the history for the riderId
    const snapshot = await historyRef.where("riderId", "==", riderId).get();

    let totalAmountEarned = 0;

    // Loop through the history records and calculate the total amount earned
    snapshot.forEach((childSnapshot) => {
      const historyEntry = childSnapshot.data();
      totalAmountEarned += historyEntry.price || 0; // Assuming there's an 'amountEarned' field in each history entry
    });

    res.status(200).send({totalAmountEarned: totalAmountEarned});
  } catch (error) {
    console.error("Error calculating total amount earned:", error);
    res.status(500).send({
      error: error,
    });
  }
});
