/* eslint-disable max-len */
const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {dispatchPriority, isDispatchable, riderMatchesIris} = require("./iris-core");

const sendPackage = functions.https.onCall(async (data, context) => {
  try {
    const toRadians = (degrees) => {
      return degrees * (Math.PI / 180);
    };
    const {requestId} = data;
    // Check if the user is authenticated
    if (!context.auth) {
      // Throw an error if no authentication is present
      throw new functions.https.HttpsError("unauthenticated",
          "User must be authenticated to call this function.");
    }

    // Get the authenticated user's UID
    const uid = context.auth.uid;

    // const userRef = await getFirestore().collection("users").doc(uid).get();
    const snapshot = await getFirestore().collection("deliveryRequests") .where("requestId", "==", requestId).get();
    const deliveryRequest = snapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

    if (deliveryRequest.length === 0) {
      return {message: "Delivery request not found"};
    }

    if (!isDispatchable(deliveryRequest[0])) {
      return {
        message: "Delivery request is not dispatchable by Iris.",
        requestId: requestId,
        irisStatus: deliveryRequest[0].iris && deliveryRequest[0].iris.status,
      };
    }
    const privateDoc = await getFirestore()
        .collection("irisPrivate")
        .doc(deliveryRequest[0].requestId || deliveryRequest[0].id)
        .get();
    if (privateDoc.exists) {
      deliveryRequest[0].irisPrivate = privateDoc.data();
    }

    // console.log(`${deliveryRequest[0].pickupPosition.geopoint.latitude}, ${deliveryRequest[0].pickupPosition.geopoint.longitude}`);

    // Create a reference point
    // eslint-disable-next-line new-cap
    const pickupPoint = {
      latitude: deliveryRequest[0].pickupPosition.geopoint.latitude,
      longitude: deliveryRequest[0].pickupPosition.geopoint.longitude,
    };

    // Fetch all riders
    const ridersSnapshot = await getFirestore().collection("riders")
        .where("status", "==", "online")
        .get();

    // console.log(ridersSnapshot.docs);

    // Calculate distances
    const ridersWithDistances = await Promise.all(
        ridersSnapshot.docs
            .filter((doc) => {
              const riderData = doc.data();
              if (!riderMatchesIris(riderData, deliveryRequest[0])) return false;
              return riderData.position &&
                 riderData.position.geopoint &&
                 riderData.position.geopoint.latitude &&
                 riderData.position.geopoint.longitude;
            })
            .map(async (doc) => {
              try {
                const riderData = doc.data();
                const riderLocation = riderData.position.geopoint;

                // Ensure valid coordinates
                if (!riderLocation.latitude || !riderLocation.longitude) {
                  return null;
                }

                // Haversine formula for distance calculation
                const R = 6371; // Earth's radius in kilometers
                const dLat = toRadians(riderLocation.latitude - pickupPoint.latitude);
                const dLon = toRadians(riderLocation.longitude - pickupPoint.longitude);

                const a =
              Math.sin(dLat/2) * Math.sin(dLat/2) +
              Math.cos(toRadians(pickupPoint.latitude)) *
              Math.cos(toRadians(riderLocation.latitude)) *
              Math.sin(dLon/2) * Math.sin(dLon/2);

                const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
                const distance = R * c; // Distance in kilometers

                return {
                  id: doc.id,
                  ...riderData,
                  distanceFromPickup: distance,
                };
              } catch (error) {
                console.error("Error processing rider:", error);
                return null;
              }
            }),
    );


    console.log(ridersWithDistances);

    // Filter out null values and sort
    const closestRiders = ridersWithDistances
        .filter((rider) => rider !== null)
        .sort((a, b) => dispatchPriority(deliveryRequest[0]) === 1 ?
          a.distanceFromPickup - b.distanceFromPickup :
          a.distanceFromPickup - b.distanceFromPickup)
        .slice(0, 5);

    closestRiders.forEach(async (rider) => {
      console.log(rider);
      console.log(rider.fcmToken);
      const message = {
        apns: {
          payload: {
            aps: {
              "content-available": 1,
            },
          },
        },
        data: {
          "type": "broadcast-request",
          "data": JSON.stringify(rider),
        },
        // notification: {
        //   title: `${req.user.firstName}`,
        //   body: text,
        // },
        token: rider.fcmToken,

      };

      await getMessaging().send(message).then(
          (response)=> {
            console.log(`Successfully sent message: ${response}`);
            // console.log(`token: ${metadata.pushToken}`);
          },
      ).catch((err)=>{
        //   console.log(err)
        // console.log('new error')
      });
    });

    // Your function logic here
    return {
      message: `Endpoint accessed by user ${uid}`,
      requestId: requestId,
      request: deliveryRequest,
      coordinates: `${deliveryRequest[0].pickupPosition[0]}, ${deliveryRequest[0].pickupPosition[1]}`,
      closestRiders: closestRiders,
      // Return your actual response data
    };
  } catch (e) {
    return {
      error: e,
    };
  }
});


module.exports = sendPackage;
