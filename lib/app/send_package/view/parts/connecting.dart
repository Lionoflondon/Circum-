part of '../home.dart';

class ConnectingToCourier extends StatefulWidget {
  const ConnectingToCourier({super.key});

  @override
  ConnectingToCourierState createState() => ConnectingToCourierState();
}

class ConnectingToCourierState extends State<ConnectingToCourier> {
  double progressValue = 0;

  @override
  void initState() {
    super.initState();

    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (progressValue < 1) {
        setState(() {
          progressValue = progressValue + 0.005;
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      height: MediaQuery.of(context).size.height * 0.3,
      child: Column(
        children: [
          AppText.text('Connecting you to a courier',
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28),
          const SizedBox(height: 36),
          LinearProgressIndicator(
            value: progressValue >= 1 ? null : progressValue,
            minHeight: 4,
            backgroundColor: Color(0xFF1F292E),
            color: AppColors.primary,
          ),
          const Spacer(),
          AppButton.button(
              widget: Center(
                child: AppText.text('Cancel request',
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: () {})
        ],
      ),
    );
  }
}
