/* eslint-disable max-len */
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const functions = require("firebase-functions");
// const stripe = require("stripe")(functions.config().stripe.testkey);
const stripe = require("stripe")(functions.config().stripe.livekey);
const {v4: uuidv4} = require("uuid");

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
      console.log(intent.status);
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
    name,
    phone,
    userId,
    saveCard,
  } = req.body;

  //   const orderAmount = calculateOrderAmount(items);
  const orderAmount = amount;

  try {
    if (paymentMethodId) {
      // Create new PaymentIntent with a PaymentMethod ID from the client.
      // confirmation_method: "manual",
      let customerId;

      const userRef = await getFirestore().collection("users").doc(userId).get();

      if (userRef.exists) {
        const userData = userRef.data();
        customerId = userData.customerId || undefined;
      }

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

      // Set customerId if it exists
      if (customerId && saveCard == true) {
        params.customer = customerId;
      }

      // create customerId if it doesnt exist
      if (!customerId) {
        const customer = await stripe.customers.create({
          name: name,
          phone: phone,
        });

        customerId = customer.id;

        if (saveCard == true) {
          params.customer = customerId;
        }

        await getFirestore().collection("users").doc(userId).update({
          customerId: customer.id,
        });
      }

      const intent = await stripe.paymentIntents.create(params);
      // After create, if the PaymentIntent's status is succeeded, fulfill the order.

      // if (saveCard == true) {


      //   // Customer id in the db
      // }

      const response = generateResponse(intent);
      response.customerId = customerId;

      // const session =
      // await stripe.checkout.sessions.create({
      //   payment_intent_data: {
      //     setup_future_usage: "off_session",
      //   },
      //   customer_creation: "always",
      //   line_items: [
      //     {
      //       price: amount,
      //       quantity: 1,
      //     },
      //   ],
      //   mode: "payment",
      //   success_url: "https://example.com/success.html",
      //   cancel_url: "https://example.com/cancel.html",
      // });

      console.log(`Intent: ${intent}`);
      return res.send(response);
    }
    return res.sendStatus(400);
  } catch (e) {
    console.log(e);
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

exports.RetrieveCardDetails = functions.https.onRequest(async (req, res) => {
  try {
    const {
      customerId,
    } = req.body;
    // const customer = await stripe.customers.retrieve(customerId);

    const paymentMethods = await stripe.paymentMethods.list({
      customer: customerId,
      type: "card",
    });

    res.json(paymentMethods);
    // const cards = customer.sources.data.filter((source) => source.object === "card");
    // res.json(cards);
  } catch (error) {
    console.error(error);
    res.status(500).json({error: "Unable to retrieve cards"});
  }
});


exports.calculateEarnings = functions.https.onRequest(async (req, res) => {
  try {
    const {riderId} = req.body;

    if (!riderId) {
      return res.status(404).send({msg: "riderId is required"});
    }

    const paymentRef = await getFirestore().collection("payments").doc(riderId).get();

    let accountBalance = 0;
    if (paymentRef.exists) {
      const paymentData = paymentRef.data();
      accountBalance = paymentData.accountBalance || 0;
    }

    // Retrieve the 'history' database reference
    const historyRef = getFirestore().collection("history");

    // Query the history for the riderId
    const snapshot = await historyRef.where("riderId", "==", riderId).get();

    let totalAmountEarned = 0;

    // Loop through the history records and calculate the total amount earned
    snapshot.forEach((childSnapshot) => {
      const historyEntry = childSnapshot.data();
      totalAmountEarned += historyEntry.price || 0;
    });

    const currentDate = new Date();

    // Initialize an object to store daily earnings
    const weeklyEarnings = {
      Sun: 0,
      Mon: 0,
      Tue: 0,
      Wed: 0,
      Thu: 0,
      Fri: 0,
      Sat: 0,
    };

    // Calculate the start date of the week (assuming Sunday is the start of the week)
    const startDate = new Date(currentDate);
    startDate.setDate(startDate.getDate() - 7);

    // Calculate the end date of the week (assuming Saturday is the end of the week)
    const endDate = new Date(currentDate);
    // endDate.setDate(endDate.getDate() + (6 - endDate.getDay()));

    // Query Firestore for earnings within the current week for the given user
    const earningsSnapshot = await getFirestore().collection("history")
        .where("riderId", "==", riderId)
        .where("createdAt", ">=", startDate)
        .where("createdAt", "<=", endDate)
        .get();

    // Aggregate earnings by day
    earningsSnapshot.forEach((doc) => {
      const earningData = doc.data();

      // console.log(earningData);
      const earningDate = earningData.createdAt.toDate();
      const dayOfWeek = earningDate.toLocaleDateString("en-US", {weekday: "short"});

      weeklyEarnings[dayOfWeek] += earningData.price || 0;
    });

    // response.json(weeklyEarnings);

    res.status(200).send({
      accountBalance: accountBalance,
      totalAmountEarned: totalAmountEarned,
      totalTrips: snapshot.size,
      weeklyEarnings: weeklyEarnings,
    });
  } catch (error) {
    console.error("Error calculating total amount earned:", error);
    res.status(500).send({
      error: error,
    });
  }
});

exports.endTrip = functions.https.onRequest(async (req, res) => {
  try {
    const {riderId, requestId, riderName} = req.body;

    if (!requestId) {
      return res.status(404).send({msg: "requestId is required"});
    }

    if (!riderId) {
      return res.status(404).send({msg: "riderId is required"});
    }

    if (!riderName) {
      return res.status(404).send({msg: "riderName is required"});
    }

    // Retrieve the 'history' database reference
    const ride = await getFirestore().collection("deliveryRequests").where("requestId", "==", requestId).get();
    const rideData = ride.docs[0];
    const rideDataRes = rideData.data();

    if (!rideData.exists) {
      return res.status(404).send({msg: "Trip already completed"});
    }

    if (rideDataRes.riderId != riderId) {
      return res.status(400).send({msg: "riderId does not match"});
    }

    const rideCost = rideDataRes.price;


    const uuid1 = uuidv4();
    const uuid2 = uuidv4();
    const uuiduuid = `${uuid1}${uuid2}`;
    let riderBalance = 0;

    const paymentRef = getFirestore().collection("payments").doc(riderId);

    const getPaymentData = await paymentRef.get();
    const paymentData = getPaymentData.data();

    if (getPaymentData.exists) {
      riderBalance = paymentData.accountBalance || 0;
    }

    await paymentRef.set({
      accountBalance: riderBalance+ rideCost,
    });

    await getFirestore().collection("deliveryRequests").doc(rideData.id).update({
      "status": "completed",
      "historyId": uuiduuid,
      "updatedAt": Date.now(),
    });

    const newRideData = rideDataRes;
    newRideData.userId = rideData.id;
    newRideData.riderName = riderName;
    newRideData.status = "completed";
    newRideData.timestamp = Date.now();

    await getFirestore().collection("history").doc(uuiduuid).set(newRideData);

    res.status(200).send({historyId: uuiduuid});
  } catch (error) {
    console.error("Error calculating total amount earned:", error);
    res.status(500).send({
      error: error,
    });
  }
});

