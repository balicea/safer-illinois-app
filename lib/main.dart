/*
 * Copyright 2020 Board of Trustees of the University of Illinois.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:illinois/service/AppNavigation.dart';
import 'package:illinois/service/Auth.dart';
import 'package:illinois/service/NativeCommunicator.dart';
import 'package:illinois/service/Organizations.dart';
import 'package:illinois/service/UserProfile.dart';
import 'package:illinois/service/NotificationService.dart';
import 'package:illinois/service/Service.dart';

import 'package:illinois/service/Log.dart';
import 'package:illinois/service/Analytics.dart';
import 'package:illinois/service/FirebaseCrashlytics.dart';
import 'package:illinois/service/Storage.dart';
import 'package:illinois/service/AppLivecycle.dart';
import 'package:illinois/service/Onboarding.dart';
import 'package:illinois/service/Localization.dart';
import 'package:illinois/ui/RootPanel.dart';
import 'package:illinois/service/Styles.dart';
import 'package:illinois/ui/onboarding/OnboardingHealthIntroPanel.dart';

final AppExitListener appExitListener = AppExitListener();

void main() async {

  // https://stackoverflow.com/questions/57689492/flutter-unhandled-exception-servicesbinding-defaultbinarymessenger-was-accesse
  WidgetsFlutterBinding.ensureInitialized();

  await _init();

  // do not show the red error widget when release mode
  if (kReleaseMode) {
    ErrorWidget.builder = (FlutterErrorDetails details) => Container();
  }

  // Log app create analytics event
  Analytics().logLivecycle(name: Analytics.LogLivecycleEventCreate);

  runZonedGuarded(() async {
    runApp(App());
  }, FirebaseCrashlytics().handleZoneError);
}

Future<void> _init() async {
  NotificationService().subscribe(appExitListener, AppLivecycle.notifyStateChanged);

  Services().create();
  await Services().init();
}

Future<void> _destroy() async {

  NotificationService().unsubscribe(appExitListener);

  Services().destroy();
}

class AppExitListener implements NotificationsListener {
  
  // NotificationsListener
  @override
  void onNotification(String name, param) {
    if ((name == AppLivecycle.notifyStateChanged) && (param == AppLifecycleState.detached)) {
      Future.delayed(Duration(), () {
        _destroy();
      });
    }
  }
}

class _AppData {
  _AppState _appState;
}

class App extends StatefulWidget {

  final _AppData _data = _AppData();
  static App _instance;

  App() {
    _instance = this;
  }

  static get instance {
    return _instance;
  }

  get appState {
    return _data._appState;
  }

  _AppState createState() {
    return _data._appState = _AppState();
  }
}

class _AppState extends State<App> implements NotificationsListener {

  Key key = UniqueKey();

  @override
  void initState() {
    Log.d("App init");

    NotificationService().subscribe(this, [
      Onboarding.notifyFinished,
      Organizations.notifyOrganizationChanged,
      Organizations.notifyEnvironmentChanged,
      UserProfile.notifyProfileDeleted,
    ]);

    AppLivecycle.instance.ensureBinding();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NativeCommunicator().dismissLaunchScreen();
    });

    super.initState();
  }

  @override
  void dispose() {
    NotificationService().unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      key: key,
      localizationsDelegates: [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: Localization().supportedLocales(),
      navigatorObservers:[AppNavigation()],
      //onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      title: Localization().getStringEx('app.title', 'Safer Illinois'),
      theme: ThemeData(
          primaryColor: Styles().colors.fillColorPrimaryVariant,
          fontFamily: Styles().fontFamilies.extraBold),
      home: _homePanel,
    );
  }

  Widget get _homePanel {
    if (!Storage().onBoardingPassed) {
      if (Auth().isLoggedIn) {
        return OnboardingHealthIntroPanel(onboardingContext: {},);
      } else {
        return Onboarding().startPanel;
      }
    } else {
      return RootPanel();
    }
  }

  void _resetUI() async {
    this.setState(() {
      key = new UniqueKey();
    });
  }

  void _finishOnboarding(BuildContext context) {
    Storage().onBoardingPassed = true;
    Route routeToHome = CupertinoPageRoute(builder: (context) => RootPanel());
    Navigator.pushAndRemoveUntil(context, routeToHome, (_) => false);
  }

  // NotificationsListener

  @override
  void onNotification(String name, dynamic param) {
    if (name == Onboarding.notifyFinished) {
      _finishOnboarding(param);
    }
    else if (name == Organizations.notifyOrganizationChanged) {
      _resetUI();
    }
    else if (name == Organizations.notifyEnvironmentChanged) {
      _resetUI();
    }
    else if (name == UserProfile.notifyProfileDeleted) {
      _resetUI();
    }
  }
}
