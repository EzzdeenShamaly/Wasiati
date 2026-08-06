import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Wasiati'**
  String get appName;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navWills.
  ///
  /// In en, this message translates to:
  /// **'Wills'**
  String get navWills;

  /// No description provided for @navVault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get navVault;

  /// No description provided for @navBurial.
  ///
  /// In en, this message translates to:
  /// **'Burial'**
  String get navBurial;

  /// No description provided for @navGuided.
  ///
  /// In en, this message translates to:
  /// **'Guided'**
  String get navGuided;

  /// No description provided for @navLegacy.
  ///
  /// In en, this message translates to:
  /// **'Legacy'**
  String get navLegacy;

  /// No description provided for @navIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get navIdentity;

  /// No description provided for @navPlans.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get navPlans;

  /// No description provided for @navAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get navAdmin;

  /// No description provided for @navUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get navUsers;

  /// No description provided for @navClaims.
  ///
  /// In en, this message translates to:
  /// **'Claims'**
  String get navClaims;

  /// No description provided for @navMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonSeePlans.
  ///
  /// In en, this message translates to:
  /// **'See plans'**
  String get commonSeePlans;

  /// No description provided for @commonSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get commonSignOut;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonBackToWill.
  ///
  /// In en, this message translates to:
  /// **'Back to will'**
  String get commonBackToWill;

  /// No description provided for @wdBackToWills.
  ///
  /// In en, this message translates to:
  /// **'My wills'**
  String get wdBackToWills;

  /// No description provided for @brandTrustStrip.
  ///
  /// In en, this message translates to:
  /// **'Sealed · Witnessed · Verified'**
  String get brandTrustStrip;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get settingsThemeDarkMode;

  /// No description provided for @settingsThemeMatchSystem.
  ///
  /// In en, this message translates to:
  /// **'Match system theme'**
  String get settingsThemeMatchSystem;

  /// No description provided for @settingsRegionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Region & language'**
  String get settingsRegionLanguage;

  /// No description provided for @settingsRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get settingsRegion;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'Match device'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get settingsLanguageArabic;

  /// No description provided for @settingsRegionNote.
  ///
  /// In en, this message translates to:
  /// **'Your region sets currency, tax rules and regional accounts. It\'s fixed to your account for data-residency reasons.'**
  String get settingsRegionNote;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// No description provided for @settingsFaceApp.
  ///
  /// In en, this message translates to:
  /// **'Face ID to open the app'**
  String get settingsFaceApp;

  /// No description provided for @settingsFaceVault.
  ///
  /// In en, this message translates to:
  /// **'Face ID for the vault'**
  String get settingsFaceVault;

  /// No description provided for @settingsChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get settingsChangePassword;

  /// No description provided for @settingsChangePasswordSub.
  ///
  /// In en, this message translates to:
  /// **'We\'ll email you a secure reset link.'**
  String get settingsChangePasswordSub;

  /// No description provided for @settingsIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity verification'**
  String get settingsIdentity;

  /// No description provided for @settingsIdentitySub.
  ///
  /// In en, this message translates to:
  /// **'Manage or complete ID verification.'**
  String get settingsIdentitySub;

  /// No description provided for @settingsSignOutSub.
  ///
  /// In en, this message translates to:
  /// **'Sign out on this device.'**
  String get settingsSignOutSub;

  /// No description provided for @settingsLegal.
  ///
  /// In en, this message translates to:
  /// **'Legal & support'**
  String get settingsLegal;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get settingsPrivacy;

  /// No description provided for @settingsTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms of service'**
  String get settingsTerms;

  /// No description provided for @settingsContact.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get settingsContact;

  /// No description provided for @settingsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get settingsDeleteTitle;

  /// No description provided for @settingsDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Deletion is handled by a person to protect against fraud on an account that holds a will. Email us and we\'ll verify and erase your data within 30 days.'**
  String get settingsDeleteBody;

  /// No description provided for @settingsRequestDeletion.
  ///
  /// In en, this message translates to:
  /// **'Request deletion'**
  String get settingsRequestDeletion;

  /// No description provided for @settingsResetSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset link sent to {email}.'**
  String settingsResetSent(String email);

  /// No description provided for @settingsLinkError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link.'**
  String get settingsLinkError;

  /// No description provided for @settingsRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get settingsRoleAdmin;

  /// No description provided for @authWelcomeTagline.
  ///
  /// In en, this message translates to:
  /// **'A dignified, Sharia-compliant will and legacy — sealed, witnessed, and verified.'**
  String get authWelcomeTagline;

  /// No description provided for @authCreateYourWill.
  ///
  /// In en, this message translates to:
  /// **'Create your will'**
  String get authCreateYourWill;

  /// No description provided for @authAlreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get authAlreadyHaveAccount;

  /// No description provided for @authRegionsLine.
  ///
  /// In en, this message translates to:
  /// **'Saudi Arabia · Canada · United States'**
  String get authRegionsLine;

  /// No description provided for @authWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Wasiati'**
  String get authWelcomeBack;

  /// No description provided for @authLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Region and currency are detected from your location — you’ll confirm them while creating your will.'**
  String get authLoginSubtitle;

  /// No description provided for @authEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// No description provided for @authNoAccountCreate.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Create one'**
  String get authNoAccountCreate;

  /// No description provided for @authMoreWaysSoon.
  ///
  /// In en, this message translates to:
  /// **'more ways to sign in — soon'**
  String get authMoreWaysSoon;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authCreateAccount;

  /// No description provided for @authRegisterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your will, encrypted vault, and legacy — in one place.'**
  String get authRegisterSubtitle;

  /// No description provided for @authRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get authRegion;

  /// No description provided for @authPhoneOptional.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional, for SMS MFA)'**
  String get authPhoneOptional;

  /// No description provided for @authPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get authPhone;

  /// No description provided for @authPhoneWhy.
  ///
  /// In en, this message translates to:
  /// **'Used to sign you in and to reach your witnesses, trustee and family.'**
  String get authPhoneWhy;

  /// No description provided for @authPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the phone number we can reach you on.'**
  String get authPhoneRequired;

  /// No description provided for @authVerifyPhoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm your phone'**
  String get authVerifyPhoneTitle;

  /// No description provided for @authVerifyPhoneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to the number you just gave us. This is the number we use to sign you in, and to reach your witnesses, trustee and family.'**
  String get authVerifyPhoneSubtitle;

  /// No description provided for @authVerifyPhoneCta.
  ///
  /// In en, this message translates to:
  /// **'Confirm phone'**
  String get authVerifyPhoneCta;

  /// No description provided for @authPhoneCodeResent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way.'**
  String get authPhoneCodeResent;

  /// No description provided for @addrCountry.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get addrCountry;

  /// No description provided for @addrLine1.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get addrLine1;

  /// No description provided for @addrLine1Required.
  ///
  /// In en, this message translates to:
  /// **'Enter your street address.'**
  String get addrLine1Required;

  /// No description provided for @addrLine2Optional.
  ///
  /// In en, this message translates to:
  /// **'Apartment, suite (optional)'**
  String get addrLine2Optional;

  /// No description provided for @addrCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get addrCity;

  /// No description provided for @addrCityRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your city.'**
  String get addrCityRequired;

  /// No description provided for @addrState.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get addrState;

  /// No description provided for @addrProvince.
  ///
  /// In en, this message translates to:
  /// **'Province'**
  String get addrProvince;

  /// No description provided for @addrEmirate.
  ///
  /// In en, this message translates to:
  /// **'Emirate'**
  String get addrEmirate;

  /// No description provided for @addrRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get addrRegion;

  /// No description provided for @addrAreaRequired.
  ///
  /// In en, this message translates to:
  /// **'This is required for your country.'**
  String get addrAreaRequired;

  /// No description provided for @addrPostalCode.
  ///
  /// In en, this message translates to:
  /// **'ZIP / postal code'**
  String get addrPostalCode;

  /// No description provided for @addrPostalCodeOptional.
  ///
  /// In en, this message translates to:
  /// **'Postal code (optional)'**
  String get addrPostalCodeOptional;

  /// No description provided for @addrPostalRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your postal code.'**
  String get addrPostalRequired;

  /// No description provided for @addrPostalInvalid.
  ///
  /// In en, this message translates to:
  /// **'That postal code does not look right for this country.'**
  String get addrPostalInvalid;

  /// No description provided for @addrWhy.
  ///
  /// In en, this message translates to:
  /// **'Your address sets which law your will is written under, and appears in the final document.'**
  String get addrWhy;

  /// No description provided for @authPasswordHelper.
  ///
  /// In en, this message translates to:
  /// **'At least 10 characters'**
  String get authPasswordHelper;

  /// No description provided for @authCreateAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccountButton;

  /// No description provided for @authHaveAccountSignIn.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get authHaveAccountSignIn;

  /// No description provided for @authInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get authInvalidEmail;

  /// No description provided for @authEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get authEnterPassword;

  /// No description provided for @authUseTenChars.
  ///
  /// In en, this message translates to:
  /// **'Use at least 10 characters'**
  String get authUseTenChars;

  /// No description provided for @authGenericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get authGenericError;

  /// No description provided for @regionUnitedStates.
  ///
  /// In en, this message translates to:
  /// **'United States'**
  String get regionUnitedStates;

  /// No description provided for @regionCanada.
  ///
  /// In en, this message translates to:
  /// **'Canada'**
  String get regionCanada;

  /// No description provided for @regionSaudiArabia.
  ///
  /// In en, this message translates to:
  /// **'Saudi Arabia'**
  String get regionSaudiArabia;

  /// No description provided for @willOpeningInsert.
  ///
  /// In en, this message translates to:
  /// **'Insert an Islamic opening'**
  String get willOpeningInsert;

  /// No description provided for @willOpeningSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Begin with the bismillah and the shahada, grounded in Qur\'an and Sunnah. Optional — keep it, edit it, or clear it.'**
  String get willOpeningSubtitle;

  /// No description provided for @willOpeningFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get willOpeningFull;

  /// No description provided for @willOpeningShort.
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get willOpeningShort;

  /// No description provided for @willOpeningInserted.
  ///
  /// In en, this message translates to:
  /// **'Opening inserted — edit or clear it as you wish.'**
  String get willOpeningInserted;

  /// No description provided for @mfaTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get mfaTitle;

  /// No description provided for @mfaResendWait.
  ///
  /// In en, this message translates to:
  /// **'Resend in {n}s'**
  String mfaResendWait(int n);

  /// No description provided for @mfaResendReady.
  ///
  /// In en, this message translates to:
  /// **'Didn’t get it?'**
  String get mfaResendReady;

  /// No description provided for @mfaResend.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get mfaResend;

  /// No description provided for @mfaSubtitleSms.
  ///
  /// In en, this message translates to:
  /// **'We sent an SMS with a 6-digit code to your phone.'**
  String get mfaSubtitleSms;

  /// MFA prompt when the code was delivered over WhatsApp rather than SMS.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to your WhatsApp.'**
  String get mfaSubtitleWhatsapp;

  /// MFA prompt when the account uses an authenticator app — nothing was sent to them.
  ///
  /// In en, this message translates to:
  /// **'Open your authenticator app and enter the 6-digit code it shows.'**
  String get mfaSubtitleTotp;

  /// Security settings: heading for single-use MFA recovery codes.
  ///
  /// In en, this message translates to:
  /// **'Backup codes'**
  String get secRcTitle;

  /// No description provided for @secRcNone.
  ///
  /// In en, this message translates to:
  /// **'Not set up — you could be locked out if you lose your phone'**
  String get secRcNone;

  /// No description provided for @secRcRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} left'**
  String secRcRemaining(int count, int total);

  /// No description provided for @secRcLow.
  ///
  /// In en, this message translates to:
  /// **'Only {count} left — generate a new set'**
  String secRcLow(int count);

  /// No description provided for @secRcGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate backup codes'**
  String get secRcGenerate;

  /// No description provided for @secRcRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate a new set'**
  String get secRcRegenerate;

  /// No description provided for @secRcSaveNow.
  ///
  /// In en, this message translates to:
  /// **'Save these now. They are shown once and cannot be recovered — each one signs you in a single time if you lose your phone.'**
  String get secRcSaveNow;

  /// No description provided for @secRcReplaces.
  ///
  /// In en, this message translates to:
  /// **'Generating a new set immediately cancels your current codes.'**
  String get secRcReplaces;

  /// No description provided for @secRcCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get secRcCopy;

  /// No description provided for @secRcCopied.
  ///
  /// In en, this message translates to:
  /// **'Backup codes copied.'**
  String get secRcCopied;

  /// No description provided for @secRcDone.
  ///
  /// In en, this message translates to:
  /// **'I have saved them'**
  String get secRcDone;

  /// Security settings: heading for the TOTP second factor.
  ///
  /// In en, this message translates to:
  /// **'Authenticator app'**
  String get secTotpTitle;

  /// No description provided for @secTotpBlurb.
  ///
  /// In en, this message translates to:
  /// **'Sign in with a code from an app like Google Authenticator or 1Password. Free, works without signal, and safer than a text message.'**
  String get secTotpBlurb;

  /// No description provided for @secTotpOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get secTotpOn;

  /// No description provided for @secTotpOff.
  ///
  /// In en, this message translates to:
  /// **'Not set up'**
  String get secTotpOff;

  /// No description provided for @secTotpSetUp.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get secTotpSetUp;

  /// No description provided for @secTotpTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get secTotpTurnOff;

  /// No description provided for @secTotpScan.
  ///
  /// In en, this message translates to:
  /// **'Scan this in your authenticator app, or paste the key below, then enter the 6-digit code it shows.'**
  String get secTotpScan;

  /// No description provided for @secTotpKey.
  ///
  /// In en, this message translates to:
  /// **'Setup key'**
  String get secTotpKey;

  /// No description provided for @secTotpConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get secTotpConfirm;

  /// No description provided for @secTotpEnabled.
  ///
  /// In en, this message translates to:
  /// **'Authenticator app is on. You will no longer be texted a code.'**
  String get secTotpEnabled;

  /// No description provided for @secTotpDisabled.
  ///
  /// In en, this message translates to:
  /// **'Authenticator app turned off. Codes will be sent to you again.'**
  String get secTotpDisabled;

  /// No description provided for @secTotpCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get secTotpCodeLabel;

  /// No description provided for @mfaSubtitleEmail.
  ///
  /// In en, this message translates to:
  /// **'We emailed a 6-digit code to your inbox.'**
  String get mfaSubtitleEmail;

  /// No description provided for @mfaVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get mfaVerify;

  /// No description provided for @forgotTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get forgotTitle;

  /// No description provided for @forgotSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and we\'ll send a 6-digit code.'**
  String get forgotSubtitle;

  /// No description provided for @forgotSentBody.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for {email}, a reset link is on its way. The link expires in 1 hour.'**
  String forgotSentBody(String email);

  /// No description provided for @forgotSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get forgotSendCode;

  /// No description provided for @forgotCodeSentBody.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for {email}, a 6-digit code is on its way — by text message when a phone is on file, otherwise by email.'**
  String forgotCodeSentBody(String email);

  /// No description provided for @forgotBackToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get forgotBackToSignIn;

  /// No description provided for @forgotSendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get forgotSendResetLink;

  /// No description provided for @resetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password reset. Please sign in.'**
  String get resetSuccess;

  /// No description provided for @resetInvalidTitle.
  ///
  /// In en, this message translates to:
  /// **'Invalid reset link'**
  String get resetInvalidTitle;

  /// No description provided for @resetInvalidSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This link is missing or malformed. Request a new one.'**
  String get resetInvalidSubtitle;

  /// No description provided for @resetRequestNew.
  ///
  /// In en, this message translates to:
  /// **'Request a new link'**
  String get resetRequestNew;

  /// No description provided for @resetTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password'**
  String get resetTitle;

  /// No description provided for @resetNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get resetNewPasswordLabel;

  /// No description provided for @resetHelper.
  ///
  /// In en, this message translates to:
  /// **'At least 10 characters'**
  String get resetHelper;

  /// No description provided for @resetValidator.
  ///
  /// In en, this message translates to:
  /// **'Use at least 10 characters'**
  String get resetValidator;

  /// No description provided for @resetSubmit.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetSubmit;

  /// No description provided for @verifyEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Verification email sent.'**
  String get verifyEmailSent;

  /// No description provided for @verifyEmailVerifyingTitle.
  ///
  /// In en, this message translates to:
  /// **'Verifying your email'**
  String get verifyEmailVerifyingTitle;

  /// No description provided for @verifyEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'This verification link is invalid or has expired.'**
  String get verifyEmailInvalid;

  /// No description provided for @verifyEmailResend.
  ///
  /// In en, this message translates to:
  /// **'Resend verification email'**
  String get verifyEmailResend;

  /// No description provided for @verifyEmailVerified.
  ///
  /// In en, this message translates to:
  /// **'Your email is verified.'**
  String get verifyEmailVerified;

  /// No description provided for @verifyEmailContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get verifyEmailContinue;

  /// No description provided for @verifyEmailSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get verifyEmailSignIn;

  /// No description provided for @verifyEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get verifyEmailTitle;

  /// No description provided for @verifyEmailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check your inbox for a verification link.'**
  String get verifyEmailSubtitle;

  /// No description provided for @dashGreeting.
  ///
  /// In en, this message translates to:
  /// **'Assalamu alaikum, {name}'**
  String dashGreeting(String name);

  /// No description provided for @dashStandardPlan.
  ///
  /// In en, this message translates to:
  /// **'Standard plan'**
  String get dashStandardPlan;

  /// No description provided for @dashCreateWill.
  ///
  /// In en, this message translates to:
  /// **'Create will'**
  String get dashCreateWill;

  /// No description provided for @dashWillsLoadError.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your wills.'**
  String get dashWillsLoadError;

  /// No description provided for @dashPrimaryWill.
  ///
  /// In en, this message translates to:
  /// **'Your primary will'**
  String get dashPrimaryWill;

  /// No description provided for @dashPrimaryWillSealed.
  ///
  /// In en, this message translates to:
  /// **'Your will — sealed'**
  String get dashPrimaryWillSealed;

  /// No description provided for @dashHeirCount.
  ///
  /// In en, this message translates to:
  /// **'{count} heirs'**
  String dashHeirCount(int count);

  /// No description provided for @dashBequest.
  ///
  /// In en, this message translates to:
  /// **'{pct}% in bequests'**
  String dashBequest(String pct);

  /// No description provided for @dashSealed.
  ///
  /// In en, this message translates to:
  /// **'Sealed'**
  String get dashSealed;

  /// No description provided for @dashDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get dashDraft;

  /// No description provided for @dashViewWill.
  ///
  /// In en, this message translates to:
  /// **'View will'**
  String get dashViewWill;

  /// No description provided for @dashSharesBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Shares breakdown'**
  String get dashSharesBreakdown;

  /// No description provided for @dashBeginWill.
  ///
  /// In en, this message translates to:
  /// **'Begin your will'**
  String get dashBeginWill;

  /// No description provided for @dashBeginBody.
  ///
  /// In en, this message translates to:
  /// **'A few minutes now spares your family months later. We compute the Sharia shares as you go.'**
  String get dashBeginBody;

  /// No description provided for @dashCreateYourWill.
  ///
  /// In en, this message translates to:
  /// **'Create your will'**
  String get dashCreateYourWill;

  /// No description provided for @dashPlanLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your plan.'**
  String get dashPlanLoadError;

  /// No description provided for @dashYourPlan.
  ///
  /// In en, this message translates to:
  /// **'Your plan'**
  String get dashYourPlan;

  /// No description provided for @dashCompedAccess.
  ///
  /// In en, this message translates to:
  /// **'Comped access'**
  String get dashCompedAccess;

  /// No description provided for @dashFeatureUnlimitedEdits.
  ///
  /// In en, this message translates to:
  /// **'Unlimited will edits'**
  String get dashFeatureUnlimitedEdits;

  /// No description provided for @dashFeatureEncryptedVault.
  ///
  /// In en, this message translates to:
  /// **'Encrypted vault'**
  String get dashFeatureEncryptedVault;

  /// No description provided for @dashFeatureVideoLegacy.
  ///
  /// In en, this message translates to:
  /// **'Video legacy messages — Premium'**
  String get dashFeatureVideoLegacy;

  /// No description provided for @dashVerified.
  ///
  /// In en, this message translates to:
  /// **'Identity verified'**
  String get dashVerified;

  /// No description provided for @dashUpgradePremium.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Premium'**
  String get dashUpgradePremium;

  /// No description provided for @dashHeirs.
  ///
  /// In en, this message translates to:
  /// **'Heirs'**
  String get dashHeirs;

  /// No description provided for @dashHeirsCaption.
  ///
  /// In en, this message translates to:
  /// **'named in your will'**
  String get dashHeirsCaption;

  /// No description provided for @dashWitnesses.
  ///
  /// In en, this message translates to:
  /// **'Witnesses'**
  String get dashWitnesses;

  /// No description provided for @dashWitnessesCaption.
  ///
  /// In en, this message translates to:
  /// **'attesting your will'**
  String get dashWitnessesCaption;

  /// No description provided for @dashTrustees.
  ///
  /// In en, this message translates to:
  /// **'Trustees'**
  String get dashTrustees;

  /// No description provided for @dashTrusteesCaption.
  ///
  /// In en, this message translates to:
  /// **'who carry it out'**
  String get dashTrusteesCaption;

  /// No description provided for @dashIdPending.
  ///
  /// In en, this message translates to:
  /// **'Pending review'**
  String get dashIdPending;

  /// No description provided for @dashIdUnverified.
  ///
  /// In en, this message translates to:
  /// **'Identity not verified'**
  String get dashIdUnverified;

  /// No description provided for @dashChecklistTitle.
  ///
  /// In en, this message translates to:
  /// **'Your legacy, in order'**
  String get dashChecklistTitle;

  /// No description provided for @dashChecklistCount.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total}'**
  String dashChecklistCount(int done, int total);

  /// No description provided for @dashCkIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity verified'**
  String get dashCkIdentity;

  /// No description provided for @dashCkHeirs.
  ///
  /// In en, this message translates to:
  /// **'Heirs added'**
  String get dashCkHeirs;

  /// No description provided for @dashCkSealed.
  ///
  /// In en, this message translates to:
  /// **'Will sealed'**
  String get dashCkSealed;

  /// No description provided for @dashCkVideo.
  ///
  /// In en, this message translates to:
  /// **'Record a video message'**
  String get dashCkVideo;

  /// No description provided for @dashWillsSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Your wills'**
  String get dashWillsSummaryTitle;

  /// No description provided for @dashSealedCountLine.
  ///
  /// In en, this message translates to:
  /// **'{count} sealed · witnessed'**
  String dashSealedCountLine(int count);

  /// No description provided for @dashNoDraftLine.
  ///
  /// In en, this message translates to:
  /// **'nothing in draft'**
  String get dashNoDraftLine;

  /// No description provided for @dashDraftLbl.
  ///
  /// In en, this message translates to:
  /// **'DRAFT'**
  String get dashDraftLbl;

  /// No description provided for @dashDraftStep.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of 6'**
  String dashDraftStep(int step);

  /// No description provided for @dashContinueDraft.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get dashContinueDraft;

  /// No description provided for @dashOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get dashOpen;

  /// No description provided for @dashVault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get dashVault;

  /// No description provided for @dashSecretsStored.
  ///
  /// In en, this message translates to:
  /// **'secrets stored'**
  String get dashSecretsStored;

  /// No description provided for @dashEncryptedLocked.
  ///
  /// In en, this message translates to:
  /// **'Client-side encrypted · locked'**
  String get dashEncryptedLocked;

  /// No description provided for @dashHeirContacts.
  ///
  /// In en, this message translates to:
  /// **'Heir contacts'**
  String get dashHeirContacts;

  /// No description provided for @dashContactsMissing.
  ///
  /// In en, this message translates to:
  /// **'missing'**
  String get dashContactsMissing;

  /// No description provided for @dashContactsComplete.
  ///
  /// In en, this message translates to:
  /// **'complete'**
  String get dashContactsComplete;

  /// No description provided for @dashContactsMeta.
  ///
  /// In en, this message translates to:
  /// **'Name, mobile & email per heir'**
  String get dashContactsMeta;

  /// No description provided for @dashConfirmed.
  ///
  /// In en, this message translates to:
  /// **'confirmed'**
  String get dashConfirmed;

  /// No description provided for @dashTrustee.
  ///
  /// In en, this message translates to:
  /// **'Trustee'**
  String get dashTrustee;

  /// No description provided for @dashPendingCode.
  ///
  /// In en, this message translates to:
  /// **'pending code'**
  String get dashPendingCode;

  /// No description provided for @dashResendSms.
  ///
  /// In en, this message translates to:
  /// **'Resend SMS code'**
  String get dashResendSms;

  /// No description provided for @dashFeatureVideoLegacyUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Video legacy messages'**
  String get dashFeatureVideoLegacyUnlocked;

  /// No description provided for @dashRefReminder.
  ///
  /// In en, this message translates to:
  /// **'Share Wasiati, earn 2.5% of each friend’s first year — they get 10% off.'**
  String get dashRefReminder;

  /// No description provided for @burialTitle.
  ///
  /// In en, this message translates to:
  /// **'Burial planning'**
  String get burialTitle;

  /// No description provided for @burialSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See what a dignified Islamic burial costs in your city today, and what that would come to in small, equal contributions — no interest, no profit.'**
  String get burialSubtitle;

  /// No description provided for @burialCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get burialCity;

  /// No description provided for @burialCityHint.
  ///
  /// In en, this message translates to:
  /// **'Toronto, ON'**
  String get burialCityHint;

  /// No description provided for @burialCostToday.
  ///
  /// In en, this message translates to:
  /// **'Cost today'**
  String get burialCostToday;

  /// No description provided for @burialMaxPeriod.
  ///
  /// In en, this message translates to:
  /// **'10 years is the longest plan.'**
  String get burialMaxPeriod;

  /// No description provided for @burialSavePlan.
  ///
  /// In en, this message translates to:
  /// **'Save this estimate'**
  String get burialSavePlan;

  /// No description provided for @burialCovers.
  ///
  /// In en, this message translates to:
  /// **'Covers ghusl, kafan, janazah services, plot and burial. When prepayment opens, your grave would be reserved with a local mosque at today\'s price and your contributions held for you — we take no interest or profit. Ultimate plan, Canada & US.'**
  String get burialCovers;

  /// No description provided for @burialYearsShort.
  ///
  /// In en, this message translates to:
  /// **'{years} yrs'**
  String burialYearsShort(int years);

  /// No description provided for @burialPlanHeader.
  ///
  /// In en, this message translates to:
  /// **'YOUR BURIAL ESTIMATE'**
  String get burialPlanHeader;

  /// No description provided for @burialPlanHeaderCity.
  ///
  /// In en, this message translates to:
  /// **'YOUR BURIAL ESTIMATE — {city}'**
  String burialPlanHeaderCity(String city);

  /// No description provided for @burialAddedToSub.
  ///
  /// In en, this message translates to:
  /// **'Would be per month'**
  String get burialAddedToSub;

  /// No description provided for @burialPerMonth.
  ///
  /// In en, this message translates to:
  /// **'{money} /mo'**
  String burialPerMonth(String money);

  /// No description provided for @burialFundedBy.
  ///
  /// In en, this message translates to:
  /// **'Fully funded by'**
  String get burialFundedBy;

  /// No description provided for @burialWantRealNumber.
  ///
  /// In en, this message translates to:
  /// **'Want a real number?'**
  String get burialWantRealNumber;

  /// No description provided for @burialQuoteDesc.
  ///
  /// In en, this message translates to:
  /// **'We\'ll request a quote from Islamic funeral providers near you.'**
  String get burialQuoteDesc;

  /// No description provided for @burialRequestQuote.
  ///
  /// In en, this message translates to:
  /// **'Request a quote'**
  String get burialRequestQuote;

  /// No description provided for @burialUltimatePlan.
  ///
  /// In en, this message translates to:
  /// **'Ultimate plan (US & Canada)'**
  String get burialUltimatePlan;

  /// No description provided for @burialUltimateDesc.
  ///
  /// In en, this message translates to:
  /// **'Burial planning is part of the Ultimate plan.'**
  String get burialUltimateDesc;

  /// No description provided for @burialEstimateSummary.
  ///
  /// In en, this message translates to:
  /// **'{cost} · {months} equal contributions · no interest, no profit'**
  String burialEstimateSummary(String cost, int months);

  /// No description provided for @burialProviderQuote.
  ///
  /// In en, this message translates to:
  /// **'Provider quote: {amount}'**
  String burialProviderQuote(String amount);

  /// No description provided for @burialProviderQuoteNotes.
  ///
  /// In en, this message translates to:
  /// **'Provider quote: {amount} · {notes}'**
  String burialProviderQuoteNotes(String amount, String notes);

  /// No description provided for @burialQuoteRequested.
  ///
  /// In en, this message translates to:
  /// **'Quote requested — an admin is sourcing a real quote.'**
  String get burialQuoteRequested;

  /// No description provided for @burialRequestRealQuote.
  ///
  /// In en, this message translates to:
  /// **'Request a real quote'**
  String get burialRequestRealQuote;

  /// No description provided for @burialSavedPlans.
  ///
  /// In en, this message translates to:
  /// **'Your saved plans'**
  String get burialSavedPlans;

  /// No description provided for @burialPlanSaved.
  ///
  /// In en, this message translates to:
  /// **'Estimate saved.'**
  String get burialPlanSaved;

  /// No description provided for @burialEnterCityCost.
  ///
  /// In en, this message translates to:
  /// **'Enter a city and today\'s cost.'**
  String get burialEnterCityCost;

  /// No description provided for @adminCommerceEyebrow.
  ///
  /// In en, this message translates to:
  /// **'ADMIN — COMMERCE'**
  String get adminCommerceEyebrow;

  /// No description provided for @adminCommerceTitle.
  ///
  /// In en, this message translates to:
  /// **'Catalog, promotions & offers'**
  String get adminCommerceTitle;

  /// No description provided for @adminCommerceTabPlans.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get adminCommerceTabPlans;

  /// No description provided for @adminCommerceTabPromotions.
  ///
  /// In en, this message translates to:
  /// **'Promotions'**
  String get adminCommerceTabPromotions;

  /// No description provided for @adminCommerceTabOffers.
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get adminCommerceTabOffers;

  /// No description provided for @adminConsoleTitle.
  ///
  /// In en, this message translates to:
  /// **'Console'**
  String get adminConsoleTitle;

  /// No description provided for @adminConsolePill.
  ///
  /// In en, this message translates to:
  /// **'ADMIN'**
  String get adminConsolePill;

  /// No description provided for @adminPlanPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Price ({currency})'**
  String adminPlanPriceLabel(String currency);

  /// No description provided for @adminPlanPriceUpdated.
  ///
  /// In en, this message translates to:
  /// **'Price updated — live everywhere.'**
  String get adminPlanPriceUpdated;

  /// No description provided for @adminPlanEditPrice.
  ///
  /// In en, this message translates to:
  /// **'Edit price'**
  String get adminPlanEditPrice;

  /// No description provided for @adminPromoNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New promotion'**
  String get adminPromoNewTitle;

  /// No description provided for @adminPromoCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code (e.g. LAUNCH25)'**
  String get adminPromoCodeLabel;

  /// No description provided for @adminPromoTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get adminPromoTypeLabel;

  /// No description provided for @adminPromoTypePercent.
  ///
  /// In en, this message translates to:
  /// **'Percent off'**
  String get adminPromoTypePercent;

  /// No description provided for @adminPromoTypeAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount off (USD)'**
  String get adminPromoTypeAmount;

  /// No description provided for @adminPromoValuePercentLabel.
  ///
  /// In en, this message translates to:
  /// **'Percent (1-100)'**
  String get adminPromoValuePercentLabel;

  /// No description provided for @adminPromoValueAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount (cents)'**
  String get adminPromoValueAmountLabel;

  /// No description provided for @adminPromoCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get adminPromoCreate;

  /// No description provided for @adminPromoCreated.
  ///
  /// In en, this message translates to:
  /// **'Promotion created.'**
  String get adminPromoCreated;

  /// No description provided for @adminPromoNewButton.
  ///
  /// In en, this message translates to:
  /// **'New promo'**
  String get adminPromoNewButton;

  /// No description provided for @adminPromoEmpty.
  ///
  /// In en, this message translates to:
  /// **'No promotions yet.'**
  String get adminPromoEmpty;

  /// No description provided for @adminPromoUsed.
  ///
  /// In en, this message translates to:
  /// **'used {count}×'**
  String adminPromoUsed(int count);

  /// No description provided for @adminPromoLimitsSection.
  ///
  /// In en, this message translates to:
  /// **'Limits'**
  String get adminPromoLimitsSection;

  /// No description provided for @adminPromoMaxRedemptionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Max redemptions'**
  String get adminPromoMaxRedemptionsLabel;

  /// No description provided for @adminPromoMaxRedemptionsHelper.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for unlimited'**
  String get adminPromoMaxRedemptionsHelper;

  /// No description provided for @adminPromoStartsAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get adminPromoStartsAtLabel;

  /// No description provided for @adminPromoEndsAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get adminPromoEndsAtLabel;

  /// No description provided for @adminPromoDateAny.
  ///
  /// In en, this message translates to:
  /// **'Any time'**
  String get adminPromoDateAny;

  /// No description provided for @adminPromoDateClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get adminPromoDateClear;

  /// No description provided for @adminPromoErrorEndBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'The end date must be after the start date.'**
  String get adminPromoErrorEndBeforeStart;

  /// No description provided for @adminPromoErrorCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a code.'**
  String get adminPromoErrorCodeRequired;

  /// No description provided for @adminPromoUsedOf.
  ///
  /// In en, this message translates to:
  /// **'{used} of {max} used'**
  String adminPromoUsedOf(int used, int max);

  /// No description provided for @adminPromoWindowFrom.
  ///
  /// In en, this message translates to:
  /// **'from {date}'**
  String adminPromoWindowFrom(String date);

  /// No description provided for @adminPromoWindowUntil.
  ///
  /// In en, this message translates to:
  /// **'until {date}'**
  String adminPromoWindowUntil(String date);

  /// No description provided for @adminPromoStatusLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get adminPromoStatusLive;

  /// No description provided for @adminPromoStatusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get adminPromoStatusScheduled;

  /// No description provided for @adminPromoStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get adminPromoStatusExpired;

  /// No description provided for @adminPromoStatusExhausted.
  ///
  /// In en, this message translates to:
  /// **'Limit reached'**
  String get adminPromoStatusExhausted;

  /// No description provided for @adminPromoStatusInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get adminPromoStatusInactive;

  /// No description provided for @adminPromoEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit promotion'**
  String get adminPromoEditTitle;

  /// No description provided for @adminPromoEditTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get adminPromoEditTooltip;

  /// No description provided for @adminPromoUpdated.
  ///
  /// In en, this message translates to:
  /// **'Promotion updated.'**
  String get adminPromoUpdated;

  /// No description provided for @adminPromoArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get adminPromoArchive;

  /// No description provided for @adminPromoArchived.
  ///
  /// In en, this message translates to:
  /// **'Promotion archived — it can be reinstated at any time.'**
  String get adminPromoArchived;

  /// No description provided for @adminPromoReinstate.
  ///
  /// In en, this message translates to:
  /// **'Reinstate'**
  String get adminPromoReinstate;

  /// No description provided for @adminPromoReinstated.
  ///
  /// In en, this message translates to:
  /// **'Promotion reinstated.'**
  String get adminPromoReinstated;

  /// No description provided for @adminPromoFirstTimeOnlyLabel.
  ///
  /// In en, this message translates to:
  /// **'First subscription only'**
  String get adminPromoFirstTimeOnlyLabel;

  /// No description provided for @adminPromoFirstTimeOnlyHelper.
  ///
  /// In en, this message translates to:
  /// **'Customers who have bought before are refused this code.'**
  String get adminPromoFirstTimeOnlyHelper;

  /// No description provided for @adminOfferEmpty.
  ///
  /// In en, this message translates to:
  /// **'No offers yet.'**
  String get adminOfferEmpty;

  /// No description provided for @adminOfferLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get adminOfferLive;

  /// No description provided for @adminOfferOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get adminOfferOff;

  /// No description provided for @adminOfferEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit offer'**
  String get adminOfferEditTitle;

  /// No description provided for @adminOfferEditTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get adminOfferEditTooltip;

  /// No description provided for @adminOfferTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get adminOfferTitleLabel;

  /// No description provided for @adminOfferSubtitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Subtitle'**
  String get adminOfferSubtitleLabel;

  /// No description provided for @adminOfferBadgeLabel.
  ///
  /// In en, this message translates to:
  /// **'Badge'**
  String get adminOfferBadgeLabel;

  /// No description provided for @adminOfferCtaLabel.
  ///
  /// In en, this message translates to:
  /// **'Button label'**
  String get adminOfferCtaLabel;

  /// No description provided for @adminOfferErrorTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'A title is required.'**
  String get adminOfferErrorTitleRequired;

  /// No description provided for @adminOfferSaved.
  ///
  /// In en, this message translates to:
  /// **'Offer updated.'**
  String get adminOfferSaved;

  /// No description provided for @adminOfferActivated.
  ///
  /// In en, this message translates to:
  /// **'Offer is live.'**
  String get adminOfferActivated;

  /// No description provided for @adminOfferDeactivated.
  ///
  /// In en, this message translates to:
  /// **'Offer switched off.'**
  String get adminOfferDeactivated;

  /// No description provided for @adminOfferDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this offer?'**
  String get adminOfferDeleteTitle;

  /// No description provided for @adminOfferDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'It disappears from the storefront immediately. Unlike a promotion, a deleted offer cannot be reinstated.'**
  String get adminOfferDeleteBody;

  /// No description provided for @adminOfferDeleted.
  ///
  /// In en, this message translates to:
  /// **'Offer deleted.'**
  String get adminOfferDeleted;

  /// No description provided for @relHusband.
  ///
  /// In en, this message translates to:
  /// **'Husband'**
  String get relHusband;

  /// No description provided for @relWife.
  ///
  /// In en, this message translates to:
  /// **'Wife'**
  String get relWife;

  /// No description provided for @relSon.
  ///
  /// In en, this message translates to:
  /// **'Son'**
  String get relSon;

  /// No description provided for @relDaughter.
  ///
  /// In en, this message translates to:
  /// **'Daughter'**
  String get relDaughter;

  /// No description provided for @relFather.
  ///
  /// In en, this message translates to:
  /// **'Father'**
  String get relFather;

  /// No description provided for @relMother.
  ///
  /// In en, this message translates to:
  /// **'Mother'**
  String get relMother;

  /// No description provided for @relGrandfather.
  ///
  /// In en, this message translates to:
  /// **'Grandfather'**
  String get relGrandfather;

  /// No description provided for @relGrandmother.
  ///
  /// In en, this message translates to:
  /// **'Grandmother'**
  String get relGrandmother;

  /// No description provided for @relBrother.
  ///
  /// In en, this message translates to:
  /// **'Brother (full)'**
  String get relBrother;

  /// No description provided for @relSister.
  ///
  /// In en, this message translates to:
  /// **'Sister (full)'**
  String get relSister;

  /// No description provided for @relMaternalSibling.
  ///
  /// In en, this message translates to:
  /// **'Sibling (maternal half)'**
  String get relMaternalSibling;

  /// No description provided for @relSonSon.
  ///
  /// In en, this message translates to:
  /// **'Son\'s son (grandson)'**
  String get relSonSon;

  /// No description provided for @relSonDaughter.
  ///
  /// In en, this message translates to:
  /// **'Son\'s daughter (granddaughter)'**
  String get relSonDaughter;

  /// No description provided for @relPaternalGrandmother.
  ///
  /// In en, this message translates to:
  /// **'Grandmother (paternal)'**
  String get relPaternalGrandmother;

  /// No description provided for @relMaternalGrandmother.
  ///
  /// In en, this message translates to:
  /// **'Grandmother (maternal)'**
  String get relMaternalGrandmother;

  /// No description provided for @relConsanguineBrother.
  ///
  /// In en, this message translates to:
  /// **'Brother (paternal half)'**
  String get relConsanguineBrother;

  /// No description provided for @relConsanguineSister.
  ///
  /// In en, this message translates to:
  /// **'Sister (paternal half)'**
  String get relConsanguineSister;

  /// No description provided for @relFullNephew.
  ///
  /// In en, this message translates to:
  /// **'Brother\'s son (full)'**
  String get relFullNephew;

  /// No description provided for @relConsanguineNephew.
  ///
  /// In en, this message translates to:
  /// **'Brother\'s son (paternal half)'**
  String get relConsanguineNephew;

  /// No description provided for @relFullUncle.
  ///
  /// In en, this message translates to:
  /// **'Paternal uncle (full)'**
  String get relFullUncle;

  /// No description provided for @relConsanguineUncle.
  ///
  /// In en, this message translates to:
  /// **'Paternal uncle (paternal half)'**
  String get relConsanguineUncle;

  /// No description provided for @relFullCousin.
  ///
  /// In en, this message translates to:
  /// **'Paternal uncle\'s son (full)'**
  String get relFullCousin;

  /// No description provided for @relConsanguineCousin.
  ///
  /// In en, this message translates to:
  /// **'Paternal uncle\'s son (paternal half)'**
  String get relConsanguineCousin;

  /// No description provided for @cwPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your will'**
  String get cwPageTitle;

  /// No description provided for @cwStep1.
  ///
  /// In en, this message translates to:
  /// **'Step 1 of 4 — Family & heirs'**
  String get cwStep1;

  /// No description provided for @cwFamilyHeirs.
  ///
  /// In en, this message translates to:
  /// **'Family & heirs'**
  String get cwFamilyHeirs;

  /// No description provided for @cwWhoHeirs.
  ///
  /// In en, this message translates to:
  /// **'Who are your heirs?'**
  String get cwWhoHeirs;

  /// No description provided for @cwHeirsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add family members; shares are computed automatically to the fara\'id.'**
  String get cwHeirsSubtitle;

  /// No description provided for @cwSavedAuto.
  ///
  /// In en, this message translates to:
  /// **'Draft saved — you can leave and continue later'**
  String get cwSavedAuto;

  /// No description provided for @cwFillAi.
  ///
  /// In en, this message translates to:
  /// **'Ask Ameen to fill it'**
  String get cwFillAi;

  /// No description provided for @cwBack.
  ///
  /// In en, this message translates to:
  /// **'‹ Back'**
  String get cwBack;

  /// No description provided for @cwContinueBequests.
  ///
  /// In en, this message translates to:
  /// **'Continue to bequests ›'**
  String get cwContinueBequests;

  /// No description provided for @cwStep2.
  ///
  /// In en, this message translates to:
  /// **'STEP 2 OF 4 — BEQUEST'**
  String get cwStep2;

  /// No description provided for @cwBequestTitle.
  ///
  /// In en, this message translates to:
  /// **'The free third'**
  String get cwBequestTitle;

  /// No description provided for @cwBequestSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Up to one third of your estate may go to charity or to someone who does not inherit — a stepchild, a friend. Your heirs\' fixed shares are never touched.'**
  String get cwBequestSubtitle;

  /// No description provided for @cwBequestWhoLabel.
  ///
  /// In en, this message translates to:
  /// **'Who receives it'**
  String get cwBequestWhoLabel;

  /// No description provided for @cwBequestWhoHint.
  ///
  /// In en, this message translates to:
  /// **'A charity, a stepchild, a friend…'**
  String get cwBequestWhoHint;

  /// No description provided for @cwBequestAmount.
  ///
  /// In en, this message translates to:
  /// **'Bequest'**
  String get cwBequestAmount;

  /// No description provided for @cwOfEstate.
  ///
  /// In en, this message translates to:
  /// **'of the estate'**
  String get cwOfEstate;

  /// No description provided for @cwOfFreeThird.
  ///
  /// In en, this message translates to:
  /// **'of the free third'**
  String get cwOfFreeThird;

  /// No description provided for @cwWithinCap.
  ///
  /// In en, this message translates to:
  /// **'Within the one-third cap'**
  String get cwWithinCap;

  /// No description provided for @cwBequestHelp.
  ///
  /// In en, this message translates to:
  /// **'Drag to set how much to leave. It can never exceed one third (⅓) — the fara\'id shares always come first.'**
  String get cwBequestHelp;

  /// No description provided for @cwCreateMyWill.
  ///
  /// In en, this message translates to:
  /// **'Create my will ›'**
  String get cwCreateMyWill;

  /// No description provided for @cwBequestNameNeeded.
  ///
  /// In en, this message translates to:
  /// **'Name who receives the bequest first.'**
  String get cwBequestNameNeeded;

  /// No description provided for @cwContinueWords.
  ///
  /// In en, this message translates to:
  /// **'Continue to words ›'**
  String get cwContinueWords;

  /// No description provided for @cwStep3.
  ///
  /// In en, this message translates to:
  /// **'STEP 3 OF 4 — WORDS'**
  String get cwStep3;

  /// No description provided for @cwWordsTitle.
  ///
  /// In en, this message translates to:
  /// **'Words for my family'**
  String get cwWordsTitle;

  /// No description provided for @cwWordsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A personal message inside your will — released with it, up to 5,000 characters.'**
  String get cwWordsSubtitle;

  /// No description provided for @cwWordsHint.
  ///
  /// In en, this message translates to:
  /// **'In the name of Allah, the Most Gracious, the Most Merciful. This is what I enjoin upon my family: I testify that there is no god but Allah…    ↵ Press Enter to start from the classic wasiyya — or write your own'**
  String get cwWordsHint;

  /// No description provided for @cwWordsDefault.
  ///
  /// In en, this message translates to:
  /// **'In the name of Allah, the Most Gracious, the Most Merciful.\n\nThis is what I enjoin upon my family: I testify that there is no god but Allah, alone without partner, and that Muhammad صلى الله عليه وسلم is His servant and Messenger; that Paradise is true, the Fire is true, and the Hour is coming without doubt, and Allah will resurrect those in the graves.\n\nI enjoin you to fear Allah, to set right what is between you, and to obey Allah and His Messenger if you are believers. Hold to prayer, be dutiful to one another, and forgive me my shortcomings. Settle my debts, and remember me in your duʿa\'.'**
  String get cwWordsDefault;

  /// No description provided for @cwRelation.
  ///
  /// In en, this message translates to:
  /// **'Relation'**
  String get cwRelation;

  /// No description provided for @cwName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get cwName;

  /// No description provided for @cwLivePreview.
  ///
  /// In en, this message translates to:
  /// **'LIVE FARA’ID PREVIEW'**
  String get cwLivePreview;

  /// No description provided for @cwLivePreviewShort.
  ///
  /// In en, this message translates to:
  /// **'FARA\'ID'**
  String get cwLivePreviewShort;

  /// No description provided for @cwHeirCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 heir} other{{count} heirs}}'**
  String cwHeirCount(int count);

  /// No description provided for @cwUpdatesAsType.
  ///
  /// In en, this message translates to:
  /// **'updates as you type'**
  String get cwUpdatesAsType;

  /// No description provided for @cwPreviewFootnote.
  ///
  /// In en, this message translates to:
  /// **'Shares follow the fara\'id for the heirs you\'ve entered. The server recomputes and enforces the final split when you continue.'**
  String get cwPreviewFootnote;

  /// No description provided for @cwAddHeirPrompt.
  ///
  /// In en, this message translates to:
  /// **'Add an heir to see the live breakdown.'**
  String get cwAddHeirPrompt;

  /// No description provided for @cwSexLabel.
  ///
  /// In en, this message translates to:
  /// **'I am'**
  String get cwSexLabel;

  /// No description provided for @cwMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get cwMale;

  /// No description provided for @cwFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get cwFemale;

  /// No description provided for @cwWivesLabel.
  ///
  /// In en, this message translates to:
  /// **'Spouses'**
  String get cwWivesLabel;

  /// No description provided for @cwSpousesHelp.
  ///
  /// In en, this message translates to:
  /// **'Up to 4 wives — the spousal share is divided equally among them.'**
  String get cwSpousesHelp;

  /// No description provided for @cwHusbandLabel.
  ///
  /// In en, this message translates to:
  /// **'Husband'**
  String get cwHusbandLabel;

  /// No description provided for @cwChildrenLabel.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get cwChildrenLabel;

  /// No description provided for @cwParentsLabel.
  ///
  /// In en, this message translates to:
  /// **'Parents'**
  String get cwParentsLabel;

  /// No description provided for @cwFamilyFootnote.
  ///
  /// In en, this message translates to:
  /// **'Only living heirs at the time of death inherit. You\'ll confirm your region while creating your will.'**
  String get cwFamilyFootnote;

  /// No description provided for @cwAddExtended.
  ///
  /// In en, this message translates to:
  /// **'Add extended family — grandparents, siblings, uncles, cousins'**
  String get cwAddExtended;

  /// No description provided for @cwExtendedFamily.
  ///
  /// In en, this message translates to:
  /// **'Extended family'**
  String get cwExtendedFamily;

  /// No description provided for @cwSettleFootnote.
  ///
  /// In en, this message translates to:
  /// **'Debts you owe and any bequest (≤ ⅓) are settled before these shares.'**
  String get cwSettleFootnote;

  /// No description provided for @cwBeforeShares.
  ///
  /// In en, this message translates to:
  /// **'BEFORE SHARES ARE DIVIDED'**
  String get cwBeforeShares;

  /// No description provided for @cwStep1Funeral.
  ///
  /// In en, this message translates to:
  /// **'Funeral expenses'**
  String get cwStep1Funeral;

  /// No description provided for @cwStep2Debts.
  ///
  /// In en, this message translates to:
  /// **'Debts you owe (owed money) — settled in full first'**
  String get cwStep2Debts;

  /// No description provided for @cwStep3Bequest.
  ///
  /// In en, this message translates to:
  /// **'Bequest — up to one third of what remains'**
  String get cwStep3Bequest;

  /// No description provided for @cwSharesApplyRest.
  ///
  /// In en, this message translates to:
  /// **'The shares below apply to the rest of the estate.'**
  String get cwSharesApplyRest;

  /// No description provided for @cwMadhhabQuestion.
  ///
  /// In en, this message translates to:
  /// **'Which school of jurisprudence (fiqh) do you follow?'**
  String get cwMadhhabQuestion;

  /// No description provided for @cwMadhhabJumhur.
  ///
  /// In en, this message translates to:
  /// **'Jumhūr — the majority position as applied today, followed by Mālikī, Shāfiʿī and Ḥanbalī communities'**
  String get cwMadhhabJumhur;

  /// No description provided for @cwMadhhabHanafi.
  ///
  /// In en, this message translates to:
  /// **'Ḥanafī — differs where a grandfather inherits alongside siblings'**
  String get cwMadhhabHanafi;

  /// No description provided for @cwMadhhabMaliki.
  ///
  /// In en, this message translates to:
  /// **'Maliki'**
  String get cwMadhhabMaliki;

  /// No description provided for @cwMadhhabShafii.
  ///
  /// In en, this message translates to:
  /// **'Shafi\'i'**
  String get cwMadhhabShafii;

  /// No description provided for @cwMadhhabHanbali.
  ///
  /// In en, this message translates to:
  /// **'Hanbali'**
  String get cwMadhhabHanbali;

  /// No description provided for @cwMadhhabNote.
  ///
  /// In en, this message translates to:
  /// **'The schools differ in one place for these heirs: whether a grandfather shares with siblings (majority) or blocks them (Ḥanafī). On returning a surplus to the heirs (radd), contemporary practice across the schools agrees.'**
  String get cwMadhhabNote;

  /// No description provided for @cwComputedPer.
  ///
  /// In en, this message translates to:
  /// **'Computed per: {school}'**
  String cwComputedPer(String school);

  /// No description provided for @cwDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'I understand this document expresses my wishes under Islamic inheritance principles and that Wasiati does not provide legal advice. Requirements vary by jurisdiction; I may need witnesses or notarization for enforceability.'**
  String get cwDisclaimer;

  /// No description provided for @cwStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of 6 — {name}'**
  String cwStepOf(String step, String name);

  /// No description provided for @cwStepName1.
  ///
  /// In en, this message translates to:
  /// **'Family & heirs'**
  String get cwStepName1;

  /// No description provided for @cwStepName2.
  ///
  /// In en, this message translates to:
  /// **'Heir registry'**
  String get cwStepName2;

  /// No description provided for @cwStepName3.
  ///
  /// In en, this message translates to:
  /// **'Witnesses, trustee & guardian'**
  String get cwStepName3;

  /// No description provided for @cwStepName4.
  ///
  /// In en, this message translates to:
  /// **'Your estate & bequest'**
  String get cwStepName4;

  /// No description provided for @cwStepName5.
  ///
  /// In en, this message translates to:
  /// **'Wishes & words'**
  String get cwStepName5;

  /// No description provided for @cwStepName6.
  ///
  /// In en, this message translates to:
  /// **'Review & confirm'**
  String get cwStepName6;

  /// No description provided for @cwNavBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get cwNavBack;

  /// No description provided for @cwNavContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get cwNavContinue;

  /// No description provided for @cwEstateTitle.
  ///
  /// In en, this message translates to:
  /// **'Your estate today'**
  String get cwEstateTitle;

  /// No description provided for @cwEstateEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit assets & loans'**
  String get cwEstateEdit;

  /// No description provided for @cwShowAllRows.
  ///
  /// In en, this message translates to:
  /// **'Show all {n} assets & loans'**
  String cwShowAllRows(String n);

  /// No description provided for @cwFxNote.
  ///
  /// In en, this message translates to:
  /// **'Foreign amounts converted to {currency} — your local currency, from your region — at today\'s rate.'**
  String cwFxNote(String currency);

  /// No description provided for @cwEstateAssets.
  ///
  /// In en, this message translates to:
  /// **'ASSETS'**
  String get cwEstateAssets;

  /// No description provided for @cwEstateLoans.
  ///
  /// In en, this message translates to:
  /// **'DEBTS'**
  String get cwEstateLoans;

  /// No description provided for @cwEstateNet.
  ///
  /// In en, this message translates to:
  /// **'NET ESTATE'**
  String get cwEstateNet;

  /// No description provided for @cwEstateNote.
  ///
  /// In en, this message translates to:
  /// **'From your inventory. Funeral costs and debts are settled first, then your bequest (max ⅓), then fara\'id shares. Vault secrets stay out of the will — they release separately, encrypted.'**
  String get cwEstateNote;

  /// No description provided for @cwEstateEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet — list what you own and owe so your family never has to search.'**
  String get cwEstateEmpty;

  /// No description provided for @cwBequestCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Bequest — the free third'**
  String get cwBequestCardTitle;

  /// No description provided for @cwBequestCardSub.
  ///
  /// In en, this message translates to:
  /// **'For charity, sadaqah jariyah, or people who don\'t inherit (a step-child, a friend). Capped at one third of the estate; heirs\' shares are never touched.'**
  String get cwBequestCardSub;

  /// No description provided for @cwBequestPctLabel.
  ///
  /// In en, this message translates to:
  /// **'Bequest — % of the free third'**
  String get cwBequestPctLabel;

  /// No description provided for @cwBequestHelpLead.
  ///
  /// In en, this message translates to:
  /// **'Up to one third of the estate may be bequeathed outside the fara\'id. Your current bequest equals'**
  String get cwBequestHelpLead;

  /// No description provided for @cwOfEstateDot.
  ///
  /// In en, this message translates to:
  /// **'of the estate.'**
  String get cwOfEstateDot;

  /// No description provided for @cwWishesCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Funeral & burial wishes'**
  String get cwWishesCardTitle;

  /// No description provided for @cwWish1.
  ///
  /// In en, this message translates to:
  /// **'Ghusl and shrouding per the Sunnah'**
  String get cwWish1;

  /// No description provided for @cwWish2.
  ///
  /// In en, this message translates to:
  /// **'A simple burial — no extravagance, no delay'**
  String get cwWish2;

  /// No description provided for @cwWish3.
  ///
  /// In en, this message translates to:
  /// **'Bury me in the nearest Muslim cemetery'**
  String get cwWish3;

  /// No description provided for @cwWish4.
  ///
  /// In en, this message translates to:
  /// **'Hold an ʿazāʾ (condolence gathering) — three days, no more'**
  String get cwWish4;

  /// No description provided for @cwWish4No.
  ///
  /// In en, this message translates to:
  /// **'No ʿazāʾ gathering — duʿāʾ suffices'**
  String get cwWish4No;

  /// No description provided for @cwWishesNote.
  ///
  /// In en, this message translates to:
  /// **'Recorded in your will so your family isn\'t guessing at the hardest moment.'**
  String get cwWishesNote;

  /// No description provided for @cwSealBtn.
  ///
  /// In en, this message translates to:
  /// **'Create & seal'**
  String get cwSealBtn;

  /// No description provided for @cwMotherLbl.
  ///
  /// In en, this message translates to:
  /// **'Mother living'**
  String get cwMotherLbl;

  /// No description provided for @cwFatherLbl.
  ///
  /// In en, this message translates to:
  /// **'Father living'**
  String get cwFatherLbl;

  /// No description provided for @cwGmotherLbl.
  ///
  /// In en, this message translates to:
  /// **'Grandmother living'**
  String get cwGmotherLbl;

  /// No description provided for @cwGmotherMaternalLbl.
  ///
  /// In en, this message translates to:
  /// **'Grandmother — mother’s mother'**
  String get cwGmotherMaternalLbl;

  /// No description provided for @cwGmotherPaternalLbl.
  ///
  /// In en, this message translates to:
  /// **'Grandmother — father’s mother'**
  String get cwGmotherPaternalLbl;

  /// No description provided for @cwGfatherLbl.
  ///
  /// In en, this message translates to:
  /// **'Grandfather (paternal) living'**
  String get cwGfatherLbl;

  /// No description provided for @cwExtendedHead.
  ///
  /// In en, this message translates to:
  /// **'EXTENDED FAMILY — COUNTED ONLY WHEN THEY QUALIFY'**
  String get cwExtendedHead;

  /// No description provided for @cwBrothersLbl.
  ///
  /// In en, this message translates to:
  /// **'Brothers (full)'**
  String get cwBrothersLbl;

  /// No description provided for @cwSistersLbl.
  ///
  /// In en, this message translates to:
  /// **'Sisters (full)'**
  String get cwSistersLbl;

  /// No description provided for @cwUnclesLbl.
  ///
  /// In en, this message translates to:
  /// **'Paternal uncles'**
  String get cwUnclesLbl;

  /// No description provided for @cwCousinsLbl.
  ///
  /// In en, this message translates to:
  /// **'Cousins (uncle\'s sons)'**
  String get cwCousinsLbl;

  /// No description provided for @cwDhawuNote.
  ///
  /// In en, this message translates to:
  /// **'If you have a son, your siblings, uncles and cousins inherit nothing — he blocks them entirely; with only daughters, an uncle may still take what remains after the fixed shares. Aunts, maternal uncles and their children are dhawu al-arham: Hanafis let them inherit when no sharer or residuary exists; Maliki and Shafi\'i schools classically do not. Step-parents, step-children and adopted children do not inherit by sharia — provide for them through your bequest (up to ⅓) in the next step.'**
  String get cwDhawuNote;

  /// No description provided for @cwPreviewNote.
  ///
  /// In en, this message translates to:
  /// **'Shares update as you edit. Each share carries its basis — shown in the review step.'**
  String get cwPreviewNote;

  /// No description provided for @cwHeirRegTitle.
  ///
  /// In en, this message translates to:
  /// **'Heir registry'**
  String get cwHeirRegTitle;

  /// No description provided for @cwHeirRegSub.
  ///
  /// In en, this message translates to:
  /// **'Full name, mobile number and email for every heir — required so the will can be released to each of them at claim time.'**
  String get cwHeirRegSub;

  /// No description provided for @cwFullNameLbl.
  ///
  /// In en, this message translates to:
  /// **'FULL NAME'**
  String get cwFullNameLbl;

  /// No description provided for @cwFullNamePh.
  ///
  /// In en, this message translates to:
  /// **'Full legal name'**
  String get cwFullNamePh;

  /// No description provided for @cwPhoneLbl.
  ///
  /// In en, this message translates to:
  /// **'PHONE'**
  String get cwPhoneLbl;

  /// No description provided for @cwEmailLbl.
  ///
  /// In en, this message translates to:
  /// **'EMAIL'**
  String get cwEmailLbl;

  /// No description provided for @cwPhonePh.
  ///
  /// In en, this message translates to:
  /// **'+966 55 123 4567'**
  String get cwPhonePh;

  /// No description provided for @cwEmailPh.
  ///
  /// In en, this message translates to:
  /// **'care@bank.com'**
  String get cwEmailPh;

  /// No description provided for @cwMinorLbl.
  ///
  /// In en, this message translates to:
  /// **'Under 18'**
  String get cwMinorLbl;

  /// No description provided for @cwGuardianNote.
  ///
  /// In en, this message translates to:
  /// **'Under 18 — the share is held in trust for them until they come of age, under the guardian set in the will flow (default: the surviving parent). Contact details route to the guardian.'**
  String get cwGuardianNote;

  /// No description provided for @cwHeirRegSeeded.
  ///
  /// In en, this message translates to:
  /// **'Pre-loaded from your family answers — these are the heirs who inherit under the fara\'id. Anyone blocked from inheriting is left out. Edit, add or remove rows as you need.'**
  String get cwHeirRegSeeded;

  /// No description provided for @cwAddHeirBtn.
  ///
  /// In en, this message translates to:
  /// **'+ Add heir'**
  String get cwAddHeirBtn;

  /// No description provided for @cwHeirRegMissing.
  ///
  /// In en, this message translates to:
  /// **'Every heir needs a full name, mobile number and email before the will can be sealed.'**
  String get cwHeirRegMissing;

  /// No description provided for @cwHeirRegDone.
  ///
  /// In en, this message translates to:
  /// **'All heirs have complete contact details'**
  String get cwHeirRegDone;

  /// No description provided for @cwRelOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get cwRelOther;

  /// No description provided for @cwWitTrustTitle.
  ///
  /// In en, this message translates to:
  /// **'Witnesses & trustee'**
  String get cwWitTrustTitle;

  /// No description provided for @cwWitTrustSub.
  ///
  /// In en, this message translates to:
  /// **'Two witnesses and a trustee confirm by SMS before the will can be sealed. You can review everything without them.'**
  String get cwWitTrustSub;

  /// No description provided for @cwRoleWitness.
  ///
  /// In en, this message translates to:
  /// **'Witness'**
  String get cwRoleWitness;

  /// No description provided for @cwRoleTrustee.
  ///
  /// In en, this message translates to:
  /// **'Trustee'**
  String get cwRoleTrustee;

  /// No description provided for @cwPendingLbl.
  ///
  /// In en, this message translates to:
  /// **'PENDING'**
  String get cwPendingLbl;

  /// No description provided for @cwConfirmedLbl.
  ///
  /// In en, this message translates to:
  /// **'CONFIRMED'**
  String get cwConfirmedLbl;

  /// No description provided for @cwWitGateNote.
  ///
  /// In en, this message translates to:
  /// **'Sealing unlocks once both witnesses and the trustee confirm — reviewing stays open meanwhile.'**
  String get cwWitGateNote;

  /// No description provided for @cwAddWitness.
  ///
  /// In en, this message translates to:
  /// **'+ Add witness'**
  String get cwAddWitness;

  /// Inline witness-minimum counter on create-will step 3, e.g. "1 of 2 required". Both numbers are pre-formatted in the locale's digits.
  ///
  /// In en, this message translates to:
  /// **'{added} of {required} required'**
  String cwWitnessCountReq(String added, String required);

  /// No description provided for @cwWitnessMinNote.
  ///
  /// In en, this message translates to:
  /// **'Add at least {required} witnesses to continue — a will cannot be signed or sealed with fewer.'**
  String cwWitnessMinNote(String required);

  /// No description provided for @cwAddTrustee.
  ///
  /// In en, this message translates to:
  /// **'+ Add trustee'**
  String get cwAddTrustee;

  /// No description provided for @cwAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get cwAdd;

  /// No description provided for @cwCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cwCancel;

  /// No description provided for @cwGuardTitle.
  ///
  /// In en, this message translates to:
  /// **'Guardianship of minor children'**
  String get cwGuardTitle;

  /// No description provided for @cwGuardSub.
  ///
  /// In en, this message translates to:
  /// **'Who cares for your children under 18. By default the surviving parent; or follow the Islamic order of guardianship; or name someone you trust.'**
  String get cwGuardSub;

  /// No description provided for @cwGParentLbl.
  ///
  /// In en, this message translates to:
  /// **'Surviving parent (default)'**
  String get cwGParentLbl;

  /// No description provided for @cwGIslamicLbl.
  ///
  /// In en, this message translates to:
  /// **'Islamic order of guardianship'**
  String get cwGIslamicLbl;

  /// No description provided for @cwGNamedLbl.
  ///
  /// In en, this message translates to:
  /// **'Name a guardian'**
  String get cwGNamedLbl;

  /// No description provided for @cwGParentNote.
  ///
  /// In en, this message translates to:
  /// **'The other parent is recorded as guardian of the person and of each minor\'s share until they come of age.'**
  String get cwGParentNote;

  /// No description provided for @cwGIslamicNote.
  ///
  /// In en, this message translates to:
  /// **'This option names no one. It directs that your children’s care, and guardianship of their share, be settled under the sharia rules and the competent court applying at the time — the schools differ, and the two need not fall to the same person. To choose the person yourself, which every school allows, use “Name a guardian”.'**
  String get cwGIslamicNote;

  /// No description provided for @cwReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review & confirm'**
  String get cwReviewTitle;

  /// No description provided for @cwReviewPeople.
  ///
  /// In en, this message translates to:
  /// **'Witnesses, trustee & guardian'**
  String get cwReviewPeople;

  /// No description provided for @cwReviewGuardianLine.
  ///
  /// In en, this message translates to:
  /// **'Guardian of minors: {who}'**
  String cwReviewGuardianLine(String who);

  /// No description provided for @cwWordsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} / 5000'**
  String cwWordsCount(int count);

  /// No description provided for @cwSealNeedsDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Tick the confirmation above to seal.'**
  String get cwSealNeedsDisclaimer;

  /// No description provided for @cwEstateSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Estate summary'**
  String get cwEstateSummaryTitle;

  /// No description provided for @cwUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get cwUpgrade;

  /// No description provided for @draftWillTitle.
  ///
  /// In en, this message translates to:
  /// **'My will — in progress'**
  String get draftWillTitle;

  /// No description provided for @draftLbl.
  ///
  /// In en, this message translates to:
  /// **'DRAFT'**
  String get draftLbl;

  /// No description provided for @draftContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get draftContinue;

  /// No description provided for @draftAutosaved.
  ///
  /// In en, this message translates to:
  /// **'autosaved'**
  String get draftAutosaved;

  /// No description provided for @rsVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'A VIDEO FOR YOUR FAMILY'**
  String get rsVideoTitle;

  /// No description provided for @rsVideoGateNote.
  ///
  /// In en, this message translates to:
  /// **'Video messages are a Premium feature. Upgrade to record encrypted video for your loved ones.'**
  String get rsVideoGateNote;

  /// No description provided for @rsVideoRecord.
  ///
  /// In en, this message translates to:
  /// **'Record video'**
  String get rsVideoRecord;

  /// No description provided for @rsVideoUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload video'**
  String get rsVideoUpload;

  /// No description provided for @rsVideoSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get rsVideoSkip;

  /// No description provided for @rsVideoNote.
  ///
  /// In en, this message translates to:
  /// **'Record now or upload a file — encrypted like the vault, released with the will. Heirs see only that a message exists.'**
  String get rsVideoNote;

  /// No description provided for @rsVideoSavedNote.
  ///
  /// In en, this message translates to:
  /// **'Encrypted · stored in your vault · plays after release'**
  String get rsVideoSavedNote;

  /// No description provided for @rsVideoDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get rsVideoDelete;

  /// No description provided for @rsVideoDeferredNote.
  ///
  /// In en, this message translates to:
  /// **'Deferred — your will is complete without it; you can add a video any time.'**
  String get rsVideoDeferredNote;

  /// No description provided for @rsVideoRecordNow.
  ///
  /// In en, this message translates to:
  /// **'Record now'**
  String get rsVideoRecordNow;

  /// No description provided for @rsVideoSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Video encrypted and saved to your vault'**
  String get rsVideoSavedToast;

  /// No description provided for @rsVideoDeferredToast.
  ///
  /// In en, this message translates to:
  /// **'Skipped — you can add a video from your will any time'**
  String get rsVideoDeferredToast;

  /// No description provided for @rsVideoMsgLabel.
  ///
  /// In en, this message translates to:
  /// **'Video message'**
  String get rsVideoMsgLabel;

  /// No description provided for @rsVideoBadFile.
  ///
  /// In en, this message translates to:
  /// **'Choose an mp4, webm or mov video file.'**
  String get rsVideoBadFile;

  /// No description provided for @wlTitle.
  ///
  /// In en, this message translates to:
  /// **'Your wills'**
  String get wlTitle;

  /// No description provided for @wlSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A sealed will can be reopened for editing on Standard and above.'**
  String get wlSubtitle;

  /// No description provided for @wlCreateWill.
  ///
  /// In en, this message translates to:
  /// **'Create will'**
  String get wlCreateWill;

  /// No description provided for @wlCapNote.
  ///
  /// In en, this message translates to:
  /// **'You can keep up to 3 drafts — delete one to start another.'**
  String get wlCapNote;

  /// No description provided for @wlNoWillsTitle.
  ///
  /// In en, this message translates to:
  /// **'No wills yet'**
  String get wlNoWillsTitle;

  /// No description provided for @wlNoWillsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your will takes about ten minutes. We guide you through every step.'**
  String get wlNoWillsSubtitle;

  /// No description provided for @wlCreateYourWill.
  ///
  /// In en, this message translates to:
  /// **'Create your will'**
  String get wlCreateYourWill;

  /// No description provided for @wlPrimaryWill.
  ///
  /// In en, this message translates to:
  /// **'My primary will'**
  String get wlPrimaryWill;

  /// No description provided for @wlAdditionalWill.
  ///
  /// In en, this message translates to:
  /// **'Additional will'**
  String get wlAdditionalWill;

  /// No description provided for @wlSealed.
  ///
  /// In en, this message translates to:
  /// **'Sealed'**
  String get wlSealed;

  /// No description provided for @wlDraftNotSealed.
  ///
  /// In en, this message translates to:
  /// **'Draft — not yet sealed'**
  String get wlDraftNotSealed;

  /// No description provided for @wlMetaSealed.
  ///
  /// In en, this message translates to:
  /// **'sealed'**
  String get wlMetaSealed;

  /// No description provided for @wlMetaDraft.
  ///
  /// In en, this message translates to:
  /// **'draft'**
  String get wlMetaDraft;

  /// No description provided for @wlMetaBequest.
  ///
  /// In en, this message translates to:
  /// **'bequest {pct}% of the free third'**
  String wlMetaBequest(String pct);

  /// No description provided for @wlTitleSealed.
  ///
  /// In en, this message translates to:
  /// **'{title} — sealed'**
  String wlTitleSealed(String title);

  /// No description provided for @wlMetaWitnesses.
  ///
  /// In en, this message translates to:
  /// **'{confirmed} of {required} witnesses confirmed'**
  String wlMetaWitnesses(int confirmed, int required);

  /// No description provided for @wlMetaUpdated.
  ///
  /// In en, this message translates to:
  /// **'updated {date}'**
  String wlMetaUpdated(String date);

  /// No description provided for @wlSealedSupersede.
  ///
  /// In en, this message translates to:
  /// **'sealed {date} — a newer sealed will supersedes it automatically'**
  String wlSealedSupersede(String date);

  /// No description provided for @wlSecondWillTitle.
  ///
  /// In en, this message translates to:
  /// **'A second will'**
  String get wlSecondWillTitle;

  /// No description provided for @wlSecondWillBody.
  ///
  /// In en, this message translates to:
  /// **'For assets in another country or a different madhhab preference.'**
  String get wlSecondWillBody;

  /// No description provided for @wlStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get wlStart;

  /// No description provided for @wlOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get wlOpen;

  /// No description provided for @wlSharesBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Shares breakdown'**
  String get wlSharesBreakdown;

  /// No description provided for @wlContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get wlContinue;

  /// No description provided for @wlCreateAnotherPrompt.
  ///
  /// In en, this message translates to:
  /// **'Need a separate will for another jurisdiction? '**
  String get wlCreateAnotherPrompt;

  /// No description provided for @wlCreateAnother.
  ///
  /// In en, this message translates to:
  /// **'Create another will'**
  String get wlCreateAnother;

  /// No description provided for @wlLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load your wills.'**
  String get wlLoadErrorTitle;

  /// No description provided for @wlTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get wlTryAgain;

  /// No description provided for @wlDeleteWill.
  ///
  /// In en, this message translates to:
  /// **'Delete will'**
  String get wlDeleteWill;

  /// No description provided for @wlDocsExtraTitle.
  ///
  /// In en, this message translates to:
  /// **'Directives — beyond the will'**
  String get wlDocsExtraTitle;

  /// No description provided for @wlPoaTitle.
  ///
  /// In en, this message translates to:
  /// **'Financial power of attorney'**
  String get wlPoaTitle;

  /// No description provided for @wlPoaSub.
  ///
  /// In en, this message translates to:
  /// **'Authorizes a trusted agent to manage your finances if you become unable to — separate from your will, effective in life.'**
  String get wlPoaSub;

  /// No description provided for @wlHcdTitle.
  ///
  /// In en, this message translates to:
  /// **'Healthcare directive'**
  String get wlHcdTitle;

  /// No description provided for @wlHcdSub.
  ///
  /// In en, this message translates to:
  /// **'Your treatment wishes and a healthcare agent, recorded with Islamic guidance in mind — separate from your will, effective in life.'**
  String get wlHcdSub;

  /// No description provided for @wlDocSigned.
  ///
  /// In en, this message translates to:
  /// **'Signed'**
  String get wlDocSigned;

  /// No description provided for @wlDocNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get wlDocNotStarted;

  /// No description provided for @wlDocPrepare.
  ///
  /// In en, this message translates to:
  /// **'Prepare & sign'**
  String get wlDocPrepare;

  /// No description provided for @wlDocEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get wlDocEdit;

  /// No description provided for @wlDocSaveSign.
  ///
  /// In en, this message translates to:
  /// **'Save & sign'**
  String get wlDocSaveSign;

  /// No description provided for @wlDocAgentNameLbl.
  ///
  /// In en, this message translates to:
  /// **'AGENT FULL NAME'**
  String get wlDocAgentNameLbl;

  /// No description provided for @wlDocWishesLbl.
  ///
  /// In en, this message translates to:
  /// **'TREATMENT WISHES'**
  String get wlDocWishesLbl;

  /// No description provided for @wlDocWishesPh.
  ///
  /// In en, this message translates to:
  /// **'e.g. no prolonged life support; consult my healthcare agent and a scholar'**
  String get wlDocWishesPh;

  /// No description provided for @wlDocAgentLine.
  ///
  /// In en, this message translates to:
  /// **'Agent: {name} · witnessed digitally'**
  String wlDocAgentLine(Object name);

  /// No description provided for @wlDocToastSigned.
  ///
  /// In en, this message translates to:
  /// **'Signed & witnessed digitally · stored with your documents'**
  String get wlDocToastSigned;

  /// No description provided for @wlDocGatedNudge.
  ///
  /// In en, this message translates to:
  /// **'Included with Premium and Ultimate.'**
  String get wlDocGatedNudge;

  /// No description provided for @wlDirectivesLink.
  ///
  /// In en, this message translates to:
  /// **'separate documents, effective during your life. Manage them from the Wills page.'**
  String get wlDirectivesLink;

  /// No description provided for @wlManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get wlManage;

  /// No description provided for @wlDeleteWillTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this will?'**
  String get wlDeleteWillTitle;

  /// No description provided for @wlDeleteWillBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes the sealed will, its shares and bequests, and the assets recorded on it. Your vault is not touched. We need to confirm it is really you.'**
  String get wlDeleteWillBody;

  /// No description provided for @wlDeleteDraftTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this draft?'**
  String get wlDeleteDraftTitle;

  /// No description provided for @wlDeleteDraftBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes the draft and everything recorded on it — heirs, shares, bequests and assets. It has not been signed or witnessed, so nothing else is affected. Your vault is not touched. We need to confirm it is really you.'**
  String get wlDeleteDraftBody;

  /// No description provided for @wlDeleteOtpLabel.
  ///
  /// In en, this message translates to:
  /// **'Enter the SMS code we sent'**
  String get wlDeleteOtpLabel;

  /// No description provided for @wlDeleteDone.
  ///
  /// In en, this message translates to:
  /// **'Will deleted.'**
  String get wlDeleteDone;

  /// No description provided for @sealTitle.
  ///
  /// In en, this message translates to:
  /// **'Your will is sealed'**
  String get sealTitle;

  /// No description provided for @sealBody.
  ///
  /// In en, this message translates to:
  /// **'Witnessed, computed to the fara\'id, encrypted and safe. May it not be needed for a very long time.'**
  String get sealBody;

  /// No description provided for @sealWry.
  ///
  /// In en, this message translates to:
  /// **'“Thank God they\'ll only be reading this when I\'m gone.”'**
  String get sealWry;

  /// No description provided for @sealViewWill.
  ///
  /// In en, this message translates to:
  /// **'View will'**
  String get sealViewWill;

  /// No description provided for @sealDownloadPdf.
  ///
  /// In en, this message translates to:
  /// **'Export PDF'**
  String get sealDownloadPdf;

  /// No description provided for @sealBackHome.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get sealBackHome;

  /// No description provided for @sealPdfComingSoon.
  ///
  /// In en, this message translates to:
  /// **'PDF export is being prepared for release.'**
  String get sealPdfComingSoon;

  /// No description provided for @rsStep3.
  ///
  /// In en, this message translates to:
  /// **'STEP 6 OF 6 — REVIEW & SEAL'**
  String get rsStep3;

  /// No description provided for @rsReadTitle.
  ///
  /// In en, this message translates to:
  /// **'Read it as your family will'**
  String get rsReadTitle;

  /// No description provided for @rsReadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check every line. After sealing, changes need a reopen (Standard and above).'**
  String get rsReadSubtitle;

  /// No description provided for @rsHeirsTitle.
  ///
  /// In en, this message translates to:
  /// **'Heirs & shares — computed to the fara\'id'**
  String get rsHeirsTitle;

  /// No description provided for @rsEditHeirs.
  ///
  /// In en, this message translates to:
  /// **'Edit heirs'**
  String get rsEditHeirs;

  /// No description provided for @rsNoHeirs.
  ///
  /// In en, this message translates to:
  /// **'No heirs recorded.'**
  String get rsNoHeirs;

  /// No description provided for @rsBequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Bequests — the free third'**
  String get rsBequestsTitle;

  /// No description provided for @rsEditBequests.
  ///
  /// In en, this message translates to:
  /// **'Edit bequests'**
  String get rsEditBequests;

  /// No description provided for @rsBequestNone.
  ///
  /// In en, this message translates to:
  /// **'None — up to a third may be left outside the shares.'**
  String get rsBequestNone;

  /// No description provided for @rsWithinCap.
  ///
  /// In en, this message translates to:
  /// **'Within the ⅓ cap.'**
  String get rsWithinCap;

  /// No description provided for @rsMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Words for my family'**
  String get rsMessageTitle;

  /// No description provided for @rsEditMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get rsEditMessage;

  /// No description provided for @rsNoMessage.
  ///
  /// In en, this message translates to:
  /// **'No personal message added yet.'**
  String get rsNoMessage;

  /// No description provided for @rsPeopleTitle.
  ///
  /// In en, this message translates to:
  /// **'Witnesses & trustee'**
  String get rsPeopleTitle;

  /// No description provided for @rsEditPeople.
  ///
  /// In en, this message translates to:
  /// **'Edit people'**
  String get rsEditPeople;

  /// No description provided for @rsNoneAdded.
  ///
  /// In en, this message translates to:
  /// **'none added'**
  String get rsNoneAdded;

  /// No description provided for @rsWitnessTrusteeLine.
  ///
  /// In en, this message translates to:
  /// **'Witnesses: {witnesses}   ·   Trustee: {trustees} (code sent on sealing)'**
  String rsWitnessTrusteeLine(String witnesses, String trustees);

  /// No description provided for @rsWitnessesInline.
  ///
  /// In en, this message translates to:
  /// **'Witnesses:'**
  String get rsWitnessesInline;

  /// No description provided for @rsTrusteeInline.
  ///
  /// In en, this message translates to:
  /// **'Trustee:'**
  String get rsTrusteeInline;

  /// No description provided for @rsCodeSentSuffix.
  ///
  /// In en, this message translates to:
  /// **'(code sent on sealing)'**
  String get rsCodeSentSuffix;

  /// No description provided for @rsDocPreview.
  ///
  /// In en, this message translates to:
  /// **'DOCUMENT PREVIEW'**
  String get rsDocPreview;

  /// No description provided for @rsLastWill.
  ///
  /// In en, this message translates to:
  /// **'Last Will & Testament'**
  String get rsLastWill;

  /// No description provided for @rsFullText.
  ///
  /// In en, this message translates to:
  /// **'Full text · English + العربية · PDF after sealing'**
  String get rsFullText;

  /// No description provided for @rsReviewedConfirm.
  ///
  /// In en, this message translates to:
  /// **'I understand Wasiati provides a fara\'id calculation for guidance and is not a fatwa or legal advice; my estate is divided according to the sharia (fara\'id). I confirm the details above are accurate.'**
  String get rsReviewedConfirm;

  /// No description provided for @rsSealMyWill.
  ///
  /// In en, this message translates to:
  /// **'Seal my will'**
  String get rsSealMyWill;

  /// No description provided for @rsSignMyWill.
  ///
  /// In en, this message translates to:
  /// **'Sign my will'**
  String get rsSignMyWill;

  /// No description provided for @rsWaitingWitnesses.
  ///
  /// In en, this message translates to:
  /// **'Waiting for witnesses'**
  String get rsWaitingWitnesses;

  /// No description provided for @rsSignedWaitingNote.
  ///
  /// In en, this message translates to:
  /// **'You\'ve signed. Your will seals once your witnesses confirm by SMS ({signed} of {required} signed).'**
  String rsSignedWaitingNote(Object signed, Object required);

  /// No description provided for @rsSignNote.
  ///
  /// In en, this message translates to:
  /// **'Your digital signature locks the will; your witnesses are then asked to confirm by SMS.'**
  String get rsSignNote;

  /// No description provided for @rsSignedNoWitnesses.
  ///
  /// In en, this message translates to:
  /// **'You\'ve signed. Add your witnesses in the will details so they can confirm by SMS — then you can seal.'**
  String get rsSignedNoWitnesses;

  /// No description provided for @rsWitnessCodesNote.
  ///
  /// In en, this message translates to:
  /// **'Witness SMS codes are sent the moment you seal.'**
  String get rsWitnessCodesNote;

  /// No description provided for @rsVerifyEmailNotice.
  ///
  /// In en, this message translates to:
  /// **'Confirm your email address before sealing — it\'s the address your witnesses, trustee and heirs will be contacted at.'**
  String get rsVerifyEmailNotice;

  /// No description provided for @rsVerifyEmailCta.
  ///
  /// In en, this message translates to:
  /// **'Verify my email'**
  String get rsVerifyEmailCta;

  /// No description provided for @wdMyPrimaryWill.
  ///
  /// In en, this message translates to:
  /// **'My primary will'**
  String get wdMyPrimaryWill;

  /// No description provided for @wdSealedEstate.
  ///
  /// In en, this message translates to:
  /// **'Sealed · {tier} estate'**
  String wdSealedEstate(String tier);

  /// No description provided for @wdDraftNotSealed.
  ///
  /// In en, this message translates to:
  /// **'Draft — not yet sealed'**
  String get wdDraftNotSealed;

  /// No description provided for @wdReopenToEdit.
  ///
  /// In en, this message translates to:
  /// **'Reopen to edit'**
  String get wdReopenToEdit;

  /// No description provided for @wdReopenSnack.
  ///
  /// In en, this message translates to:
  /// **'Reopen to edit is available on Standard and above.'**
  String get wdReopenSnack;

  /// No description provided for @wdReviseOpened.
  ///
  /// In en, this message translates to:
  /// **'A revision draft has been opened. Your sealed will stays in force until you seal the new version.'**
  String get wdReviseOpened;

  /// No description provided for @dashRefOpen.
  ///
  /// In en, this message translates to:
  /// **'View referrals'**
  String get dashRefOpen;

  /// No description provided for @settingsReferrals.
  ///
  /// In en, this message translates to:
  /// **'Referrals & account credit'**
  String get settingsReferrals;

  /// No description provided for @settingsReferralsSub.
  ///
  /// In en, this message translates to:
  /// **'Your invite code, share link and earned credit.'**
  String get settingsReferralsSub;

  /// No description provided for @wdDownloadPdf.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get wdDownloadPdf;

  /// Note under a disabled Download PDF button naming who has not signed/confirmed yet. {parties} is a ' · '-joined list, e.g. '1 witness · trustee'.
  ///
  /// In en, this message translates to:
  /// **'Waiting on: {parties}'**
  String wdExportWaitingOn(String parties);

  /// The outstanding-witness fragment of the export 'Waiting on:' note — how many witnesses still have to sign.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 witness} other{{count} witnesses}}'**
  String wdExportWaitingWitnesses(int count);

  /// The outstanding-trustee fragment of the export 'Waiting on:' note — the trustee has not confirmed yet.
  ///
  /// In en, this message translates to:
  /// **'trustee'**
  String get wdExportWaitingTrustee;

  /// Note under a disabled Download PDF button while the witness/trustee rosters are still loading.
  ///
  /// In en, this message translates to:
  /// **'Checking signatures…'**
  String get wdExportChecking;

  /// No description provided for @wdReviewSeal.
  ///
  /// In en, this message translates to:
  /// **'Review & seal ›'**
  String get wdReviewSeal;

  /// No description provided for @wdAssetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Assets & debts your heirs should know'**
  String get wdAssetsTitle;

  /// No description provided for @wdAssetsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'An inventory — accounts, property, and any money owed.'**
  String get wdAssetsSubtitle;

  /// No description provided for @wdLegacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Messages for your family'**
  String get wdLegacyTitle;

  /// No description provided for @wdLegacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record video & voice messages — released with your will.'**
  String get wdLegacySubtitle;

  /// No description provided for @wdShariaShares.
  ///
  /// In en, this message translates to:
  /// **'Shares — Fara\'id'**
  String get wdShariaShares;

  /// No description provided for @wdThHeir.
  ///
  /// In en, this message translates to:
  /// **'HEIR'**
  String get wdThHeir;

  /// No description provided for @wdThBasis.
  ///
  /// In en, this message translates to:
  /// **'BASIS'**
  String get wdThBasis;

  /// No description provided for @wdThShare.
  ///
  /// In en, this message translates to:
  /// **'SHARE'**
  String get wdThShare;

  /// No description provided for @wdNoHeirs.
  ///
  /// In en, this message translates to:
  /// **'No heirs recorded yet.'**
  String get wdNoHeirs;

  /// No description provided for @wdTotalToHeirs.
  ///
  /// In en, this message translates to:
  /// **'Total to heirs'**
  String get wdTotalToHeirs;

  /// No description provided for @wdAddBequest.
  ///
  /// In en, this message translates to:
  /// **'Add bequest'**
  String get wdAddBequest;

  /// No description provided for @wdBequestUsed.
  ///
  /// In en, this message translates to:
  /// **'{pct}% of estate used'**
  String wdBequestUsed(String pct);

  /// No description provided for @wdBequestCap.
  ///
  /// In en, this message translates to:
  /// **'cap 33.3%'**
  String get wdBequestCap;

  /// No description provided for @wdNoBequests.
  ///
  /// In en, this message translates to:
  /// **'No bequests yet — up to a third may be left outside the fara\'id shares.'**
  String get wdNoBequests;

  /// No description provided for @wdAddBequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a bequest'**
  String get wdAddBequestTitle;

  /// No description provided for @wdBeneficiary.
  ///
  /// In en, this message translates to:
  /// **'Beneficiary'**
  String get wdBeneficiary;

  /// No description provided for @wdPercentOfEstate.
  ///
  /// In en, this message translates to:
  /// **'% of estate'**
  String get wdPercentOfEstate;

  /// No description provided for @wdFreeThirdHelper.
  ///
  /// In en, this message translates to:
  /// **'Free third: max 33.33% total'**
  String get wdFreeThirdHelper;

  /// No description provided for @wdReviewerNote.
  ///
  /// In en, this message translates to:
  /// **'On your passing, a trustee submits a claim. A Wasiati reviewer verifies it before anything is released — nothing happens automatically.'**
  String get wdReviewerNote;

  /// No description provided for @wdMessageHint.
  ///
  /// In en, this message translates to:
  /// **'My dearest family — forgive my shortcomings, keep your prayers, and stay close to one another…'**
  String get wdMessageHint;

  /// No description provided for @wdMessagePartOfWill.
  ///
  /// In en, this message translates to:
  /// **'Part of your will · released with it'**
  String get wdMessagePartOfWill;

  /// No description provided for @wdSaveMessage.
  ///
  /// In en, this message translates to:
  /// **'Save message'**
  String get wdSaveMessage;

  /// No description provided for @wdMessageSaved.
  ///
  /// In en, this message translates to:
  /// **'Message saved with your will.'**
  String get wdMessageSaved;

  /// No description provided for @wdWitnesses.
  ///
  /// In en, this message translates to:
  /// **'Witnesses'**
  String get wdWitnesses;

  /// No description provided for @wdTrustees.
  ///
  /// In en, this message translates to:
  /// **'Trustees'**
  String get wdTrustees;

  /// No description provided for @wdAddWitnessTitle.
  ///
  /// In en, this message translates to:
  /// **'Add witness'**
  String get wdAddWitnessTitle;

  /// No description provided for @wdAddTrusteeTitle.
  ///
  /// In en, this message translates to:
  /// **'Add trustee'**
  String get wdAddTrusteeTitle;

  /// No description provided for @wdAddWitnessBtn.
  ///
  /// In en, this message translates to:
  /// **'+ Add witness'**
  String get wdAddWitnessBtn;

  /// No description provided for @wdAddTrusteeBtn.
  ///
  /// In en, this message translates to:
  /// **'+ Add trustee'**
  String get wdAddTrusteeBtn;

  /// No description provided for @wdFullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get wdFullName;

  /// No description provided for @wdPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone (+…)'**
  String get wdPhone;

  /// No description provided for @wdEmailOptional.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get wdEmailOptional;

  /// No description provided for @wdInviteUnreached.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t reach them by text or email — check their number, or contact them yourself.'**
  String get wdInviteUnreached;

  /// No description provided for @wdResend.
  ///
  /// In en, this message translates to:
  /// **'Resend'**
  String get wdResend;

  /// No description provided for @wdSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get wdSendCode;

  /// No description provided for @wdNoneAddedYet.
  ///
  /// In en, this message translates to:
  /// **'None added yet.'**
  String get wdNoneAddedYet;

  /// No description provided for @wdStatusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed by SMS'**
  String get wdStatusConfirmed;

  /// No description provided for @wdStatusCodeSent.
  ///
  /// In en, this message translates to:
  /// **'Code sent · awaiting confirmation'**
  String get wdStatusCodeSent;

  /// No description provided for @wdStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending — no code sent yet'**
  String get wdStatusPending;

  /// No description provided for @wdIdMatched.
  ///
  /// In en, this message translates to:
  /// **'ID matched'**
  String get wdIdMatched;

  /// No description provided for @wdCodeSentSms.
  ///
  /// In en, this message translates to:
  /// **'Verification code sent by SMS.'**
  String get wdCodeSentSms;

  /// No description provided for @wdCodeSentDev.
  ///
  /// In en, this message translates to:
  /// **'Code sent (dev): {code}'**
  String wdCodeSentDev(String code);

  /// No description provided for @wdUnpublish.
  ///
  /// In en, this message translates to:
  /// **'Unpublish'**
  String get wdUnpublish;

  /// No description provided for @wdUnpublishTitle.
  ///
  /// In en, this message translates to:
  /// **'Unpublish this will?'**
  String get wdUnpublishTitle;

  /// No description provided for @wdUnpublishBody.
  ///
  /// In en, this message translates to:
  /// **'The will goes back to draft and is no longer in force. Your signature and every witness signature are cleared — sealing again is a fresh ceremony — and witnesses who signed will be told.'**
  String get wdUnpublishBody;

  /// No description provided for @wdStepUpSmsSent.
  ///
  /// In en, this message translates to:
  /// **'Enter the confirmation code we sent to your phone by SMS.'**
  String get wdStepUpSmsSent;

  /// No description provided for @wdStepUpEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Enter the confirmation code we sent to your email.'**
  String get wdStepUpEmailSent;

  /// No description provided for @wdStepUpCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirmation code'**
  String get wdStepUpCodeLabel;

  /// No description provided for @wdUnpublishDone.
  ///
  /// In en, this message translates to:
  /// **'The will is unpublished and back in draft.'**
  String get wdUnpublishDone;

  /// No description provided for @wdErrorLoadTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load this will.'**
  String get wdErrorLoadTitle;

  /// No description provided for @assetEyebrow.
  ///
  /// In en, this message translates to:
  /// **'MY PRIMARY WILL — ASSETS'**
  String get assetEyebrow;

  /// No description provided for @assetTitle.
  ///
  /// In en, this message translates to:
  /// **'What should your heirs know about?'**
  String get assetTitle;

  /// No description provided for @assetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'An inventory, not valuations — so nothing is lost or forgotten.'**
  String get assetSubtitle;

  /// No description provided for @assetAddButton.
  ///
  /// In en, this message translates to:
  /// **'Add asset'**
  String get assetAddButton;

  /// No description provided for @assetAddLoan.
  ///
  /// In en, this message translates to:
  /// **'Add loan'**
  String get assetAddLoan;

  /// No description provided for @assetSectionAssets.
  ///
  /// In en, this message translates to:
  /// **'ASSETS'**
  String get assetSectionAssets;

  /// No description provided for @assetSectionLoans.
  ///
  /// In en, this message translates to:
  /// **'LOANS & LIABILITIES'**
  String get assetSectionLoans;

  /// No description provided for @assetInvTitle.
  ///
  /// In en, this message translates to:
  /// **'Add to the inventory'**
  String get assetInvTitle;

  /// No description provided for @assetInvEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit inventory item'**
  String get assetInvEditTitle;

  /// No description provided for @assetExport.
  ///
  /// In en, this message translates to:
  /// **'Export to Excel'**
  String get assetExport;

  /// No description provided for @assetInvAsset.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get assetInvAsset;

  /// No description provided for @assetInvLoan.
  ///
  /// In en, this message translates to:
  /// **'Loan'**
  String get assetInvLoan;

  /// No description provided for @assetColAsset.
  ///
  /// In en, this message translates to:
  /// **'ASSET'**
  String get assetColAsset;

  /// No description provided for @assetColCategory.
  ///
  /// In en, this message translates to:
  /// **'CATEGORY'**
  String get assetColCategory;

  /// No description provided for @assetColHeldWith.
  ///
  /// In en, this message translates to:
  /// **'HELD WITH'**
  String get assetColHeldWith;

  /// No description provided for @assetColPhone.
  ///
  /// In en, this message translates to:
  /// **'PHONE'**
  String get assetColPhone;

  /// No description provided for @assetColEmail.
  ///
  /// In en, this message translates to:
  /// **'EMAIL'**
  String get assetColEmail;

  /// No description provided for @assetColValue.
  ///
  /// In en, this message translates to:
  /// **'VALUE'**
  String get assetColValue;

  /// No description provided for @assetColStatus.
  ///
  /// In en, this message translates to:
  /// **'STATUS'**
  String get assetColStatus;

  /// No description provided for @assetFieldName.
  ///
  /// In en, this message translates to:
  /// **'NAME'**
  String get assetFieldName;

  /// No description provided for @assetFieldHeldWith.
  ///
  /// In en, this message translates to:
  /// **'HELD WITH / LENDER'**
  String get assetFieldHeldWith;

  /// No description provided for @assetFieldLender.
  ///
  /// In en, this message translates to:
  /// **'OWED TO / LENDER'**
  String get assetFieldLender;

  /// No description provided for @assetFieldCategory.
  ///
  /// In en, this message translates to:
  /// **'CATEGORY'**
  String get assetFieldCategory;

  /// No description provided for @assetFieldValueCurrency.
  ///
  /// In en, this message translates to:
  /// **'VALUE & CURRENCY'**
  String get assetFieldValueCurrency;

  /// No description provided for @assetFieldPhone.
  ///
  /// In en, this message translates to:
  /// **'PHONE'**
  String get assetFieldPhone;

  /// No description provided for @assetFieldEmail.
  ///
  /// In en, this message translates to:
  /// **'EMAIL'**
  String get assetFieldEmail;

  /// No description provided for @assetFieldAccountRef.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT / IBAN'**
  String get assetFieldAccountRef;

  /// No description provided for @assetHintName.
  ///
  /// In en, this message translates to:
  /// **'e.g. Gold — safe deposit'**
  String get assetHintName;

  /// No description provided for @asNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Give this asset a name so your family can identify it.'**
  String get asNameRequired;

  /// No description provided for @asValueInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter the value as a number, for example 250,000.'**
  String get asValueInvalid;

  /// No description provided for @assetHintHeldWith.
  ///
  /// In en, this message translates to:
  /// **'e.g. SNB'**
  String get assetHintHeldWith;

  /// No description provided for @assetHintValue.
  ///
  /// In en, this message translates to:
  /// **'250,000'**
  String get assetHintValue;

  /// No description provided for @assetHintPhone.
  ///
  /// In en, this message translates to:
  /// **'+966 55 123 4567'**
  String get assetHintPhone;

  /// No description provided for @assetHintEmail.
  ///
  /// In en, this message translates to:
  /// **'care@bank.com'**
  String get assetHintEmail;

  /// No description provided for @assetHintAccountRef.
  ///
  /// In en, this message translates to:
  /// **'e.g. SA03 8000 0000 6080 1016 7519'**
  String get assetHintAccountRef;

  /// No description provided for @assetRefHelper.
  ///
  /// In en, this message translates to:
  /// **'Account or IBAN plus a contact, so your heirs know exactly where the asset is and who to call. Shown masked in the list.'**
  String get assetRefHelper;

  /// No description provided for @assetCurrencyHelper.
  ///
  /// In en, this message translates to:
  /// **'The value is recorded in the currency you pick here and posts to your will exactly as entered — no conversion.'**
  String get assetCurrencyHelper;

  /// No description provided for @assetStatusManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get assetStatusManual;

  /// No description provided for @assetTotalsTitle.
  ///
  /// In en, this message translates to:
  /// **'ESTATE TOTALS'**
  String get assetTotalsTitle;

  /// No description provided for @assetTotalAssets.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get assetTotalAssets;

  /// No description provided for @assetNetEstate.
  ///
  /// In en, this message translates to:
  /// **'Net estate (after debts)'**
  String get assetNetEstate;

  /// No description provided for @assetRegionNote.
  ///
  /// In en, this message translates to:
  /// **'Canada shows RRSP · TFSA · RESP · RRIF; the US shows 401(k) · IRA · Roth · 529. Debts you owe are settled in full before the fara\'id shares are divided.'**
  String get assetRegionNote;

  /// No description provided for @assetErrorHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a suggestion above to add your first item.'**
  String get assetErrorHint;

  /// No description provided for @assetEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No assets added yet — tap a suggestion above to start.'**
  String get assetEmptyHint;

  /// No description provided for @assetVaultNote.
  ///
  /// In en, this message translates to:
  /// **'Assets link to vault secrets: heirs see the asset exists; only the trustee unlocks the details after a claim is approved.'**
  String get assetVaultNote;

  /// No description provided for @assetZakatTitle.
  ///
  /// In en, this message translates to:
  /// **'Zakat estimate'**
  String get assetZakatTitle;

  /// No description provided for @assetZakatSubline.
  ///
  /// In en, this message translates to:
  /// **'as of your hawl date · tap for the full calculation'**
  String get assetZakatSubline;

  /// No description provided for @assetZakatCaption.
  ///
  /// In en, this message translates to:
  /// **'estimated zakat due'**
  String get assetZakatCaption;

  /// No description provided for @assetAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add an asset'**
  String get assetAddTitle;

  /// No description provided for @assetLabelField.
  ///
  /// In en, this message translates to:
  /// **'Label (e.g. Apartment, Riyadh)'**
  String get assetLabelField;

  /// No description provided for @assetKindField.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get assetKindField;

  /// No description provided for @assetNotesField.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get assetNotesField;

  /// No description provided for @assetSuggestedFor.
  ///
  /// In en, this message translates to:
  /// **'SUGGESTED FOR {region}'**
  String assetSuggestedFor(String region);

  /// No description provided for @assetDebtsHeading.
  ///
  /// In en, this message translates to:
  /// **'DEBTS & LIABILITIES — settled before shares'**
  String get assetDebtsHeading;

  /// No description provided for @assetRegionKsa.
  ///
  /// In en, this message translates to:
  /// **'🇸🇦 KSA'**
  String get assetRegionKsa;

  /// No description provided for @assetRegionCa.
  ///
  /// In en, this message translates to:
  /// **'🇨🇦 CANADA'**
  String get assetRegionCa;

  /// No description provided for @assetRegionUs.
  ///
  /// In en, this message translates to:
  /// **'🇺🇸 US'**
  String get assetRegionUs;

  /// No description provided for @assetKindRealEstate.
  ///
  /// In en, this message translates to:
  /// **'Real estate'**
  String get assetKindRealEstate;

  /// No description provided for @assetKindBank.
  ///
  /// In en, this message translates to:
  /// **'Bank / account'**
  String get assetKindBank;

  /// No description provided for @assetKindPension.
  ///
  /// In en, this message translates to:
  /// **'Pension'**
  String get assetKindPension;

  /// No description provided for @assetKindVehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get assetKindVehicle;

  /// No description provided for @assetKindBusiness.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get assetKindBusiness;

  /// No description provided for @assetKindLiability.
  ///
  /// In en, this message translates to:
  /// **'Debt / owed money'**
  String get assetKindLiability;

  /// No description provided for @assetKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get assetKindOther;

  /// No description provided for @assetRealEstate.
  ///
  /// In en, this message translates to:
  /// **'Real estate'**
  String get assetRealEstate;

  /// No description provided for @assetBankAccount.
  ///
  /// In en, this message translates to:
  /// **'Bank account'**
  String get assetBankAccount;

  /// No description provided for @assetVehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get assetVehicle;

  /// No description provided for @assetBusiness.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get assetBusiness;

  /// No description provided for @assetGold.
  ///
  /// In en, this message translates to:
  /// **'Gold / jewellery'**
  String get assetGold;

  /// No description provided for @assetEndOfService.
  ///
  /// In en, this message translates to:
  /// **'End-of-service benefits'**
  String get assetEndOfService;

  /// No description provided for @assetGosiPension.
  ///
  /// In en, this message translates to:
  /// **'GOSI pension'**
  String get assetGosiPension;

  /// No description provided for @assetLoanOwed.
  ///
  /// In en, this message translates to:
  /// **'Loan / owed money'**
  String get assetLoanOwed;

  /// No description provided for @assetMortgage.
  ///
  /// In en, this message translates to:
  /// **'Mortgage'**
  String get assetMortgage;

  /// No description provided for @assetCreditCard.
  ///
  /// In en, this message translates to:
  /// **'Credit card balance'**
  String get assetCreditCard;

  /// No description provided for @assetUnpaidZakat.
  ///
  /// In en, this message translates to:
  /// **'Unpaid zakat / dues'**
  String get assetUnpaidZakat;

  /// No description provided for @assetValueField.
  ///
  /// In en, this message translates to:
  /// **'Estimated value (optional)'**
  String get assetValueField;

  /// No description provided for @assetAmountOwed.
  ///
  /// In en, this message translates to:
  /// **'Amount owed (optional)'**
  String get assetAmountOwed;

  /// No description provided for @assetCurrencyField.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get assetCurrencyField;

  /// No description provided for @lgEyebrow.
  ///
  /// In en, this message translates to:
  /// **'LEGACY MESSAGES'**
  String get lgEyebrow;

  /// No description provided for @lgTitle.
  ///
  /// In en, this message translates to:
  /// **'A few words they\'ll keep'**
  String get lgTitle;

  /// No description provided for @lgSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Released to your family alongside your will — never before. Say what a document can\'t.'**
  String get lgSubtitle;

  /// No description provided for @lgLoadError.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your wills just now.'**
  String get lgLoadError;

  /// No description provided for @lgCreateFirst.
  ///
  /// In en, this message translates to:
  /// **'Create your will first — your message is kept with it.'**
  String get lgCreateFirst;

  /// No description provided for @lgWrittenMessage.
  ///
  /// In en, this message translates to:
  /// **'Written message'**
  String get lgWrittenMessage;

  /// No description provided for @lgHint.
  ///
  /// In en, this message translates to:
  /// **'To my family — thank you for everything. When you read this…'**
  String get lgHint;

  /// No description provided for @lgSealedNote.
  ///
  /// In en, this message translates to:
  /// **'Your will is sealed — editing the message reopens it for re-sealing.'**
  String get lgSealedNote;

  /// No description provided for @lgPrivateNote.
  ///
  /// In en, this message translates to:
  /// **'Kept private until your will is released to your heirs.'**
  String get lgPrivateNote;

  /// No description provided for @lgMessageSaved.
  ///
  /// In en, this message translates to:
  /// **'Message saved.'**
  String get lgMessageSaved;

  /// No description provided for @lgVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Video & voice messages'**
  String get lgVideoTitle;

  /// No description provided for @lgVideoBadge.
  ///
  /// In en, this message translates to:
  /// **'Premium · soon'**
  String get lgVideoBadge;

  /// No description provided for @lgVideoBody.
  ///
  /// In en, this message translates to:
  /// **'Record a short video or voice note for each person you name — encrypted end-to-end and released only with your will. We\'re building this on the same encrypted vault your documents already use; it isn\'t switched on yet, so we\'re not pretending it is.'**
  String get lgVideoBody;

  /// No description provided for @lgNotifySnack.
  ///
  /// In en, this message translates to:
  /// **'We\'ll let you know the moment video messages are ready.'**
  String get lgNotifySnack;

  /// No description provided for @lgNotifyButton.
  ///
  /// In en, this message translates to:
  /// **'Notify me when it\'s ready'**
  String get lgNotifyButton;

  /// No description provided for @lgStartWill.
  ///
  /// In en, this message translates to:
  /// **'Start a will'**
  String get lgStartWill;

  /// No description provided for @kycTitle.
  ///
  /// In en, this message translates to:
  /// **'Identity verification'**
  String get kycTitle;

  /// No description provided for @kycSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Required once before your will can be sealed. Handled by Nafath in Saudi Arabia — or Stripe Identity elsewhere.'**
  String get kycSubtitle;

  /// No description provided for @kycLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your verification status.'**
  String get kycLoadError;

  /// No description provided for @kycNafathSnack.
  ///
  /// In en, this message translates to:
  /// **'Nafath verification appears when your IP is in Saudi Arabia — enabled at launch.'**
  String get kycNafathSnack;

  /// No description provided for @kycVerifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re verified'**
  String get kycVerifiedTitle;

  /// No description provided for @kycVerifiedBody.
  ///
  /// In en, this message translates to:
  /// **'Your wills can be sealed and your trustee claims will be honoured.'**
  String get kycVerifiedBody;

  /// No description provided for @kycInProgress.
  ///
  /// In en, this message translates to:
  /// **'Verification in progress'**
  String get kycInProgress;

  /// No description provided for @kycNeedsRetry.
  ///
  /// In en, this message translates to:
  /// **'Needs another try'**
  String get kycNeedsRetry;

  /// No description provided for @kycVerifyTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re not verified yet'**
  String get kycVerifyTitle;

  /// No description provided for @kycPendingBody.
  ///
  /// In en, this message translates to:
  /// **'We\'re reviewing your documents — usually under two minutes.'**
  String get kycPendingBody;

  /// No description provided for @kycRejectedBody.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify your ID. Please try again with a different document.'**
  String get kycRejectedBody;

  /// No description provided for @kycVerifyBody.
  ///
  /// In en, this message translates to:
  /// **'Verify once and your wills can be sealed, and your trustee\'s claims will be honoured.'**
  String get kycVerifyBody;

  /// No description provided for @kycVerifyNafath.
  ///
  /// In en, this message translates to:
  /// **'Verify with Nafath'**
  String get kycVerifyNafath;

  /// No description provided for @kycNafathSub.
  ///
  /// In en, this message translates to:
  /// **'Saudi national digital identity'**
  String get kycNafathSub;

  /// No description provided for @kycContinueVerification.
  ///
  /// In en, this message translates to:
  /// **'Continue verification'**
  String get kycContinueVerification;

  /// No description provided for @kycAllStates.
  ///
  /// In en, this message translates to:
  /// **'ALL STATES'**
  String get kycAllStates;

  /// No description provided for @kycStateUnverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get kycStateUnverified;

  /// No description provided for @kycStateUnverifiedSub.
  ///
  /// In en, this message translates to:
  /// **'Verify with Nafath (KSA) or Stripe Identity'**
  String get kycStateUnverifiedSub;

  /// No description provided for @kycOutsideNote.
  ///
  /// In en, this message translates to:
  /// **'Outside Saudi Arabia? You\'ll be verified with Stripe Identity instead.'**
  String get kycOutsideNote;

  /// No description provided for @kycStatePending.
  ///
  /// In en, this message translates to:
  /// **'Pending review'**
  String get kycStatePending;

  /// No description provided for @kycStatePendingSub.
  ///
  /// In en, this message translates to:
  /// **'Usually under 2 minutes; we notify you'**
  String get kycStatePendingSub;

  /// No description provided for @kycStateVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get kycStateVerified;

  /// No description provided for @kycStateVerifiedSub.
  ///
  /// In en, this message translates to:
  /// **'Unlocks sealing and claims'**
  String get kycStateVerifiedSub;

  /// No description provided for @kycStateRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get kycStateRejected;

  /// No description provided for @kycStateRejectedSub.
  ///
  /// In en, this message translates to:
  /// **'Reason shown; try again with a different document'**
  String get kycStateRejectedSub;

  /// No description provided for @vaultPassphraseShort.
  ///
  /// In en, this message translates to:
  /// **'Your passphrase must be at least 10 characters.'**
  String get vaultPassphraseShort;

  /// No description provided for @vaultAddSecretTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a secret'**
  String get vaultAddSecretTitle;

  /// No description provided for @vaultLabelField.
  ///
  /// In en, this message translates to:
  /// **'Label (e.g. Bank login)'**
  String get vaultLabelField;

  /// No description provided for @vaultSecretField.
  ///
  /// In en, this message translates to:
  /// **'Secret value (password, PIN, key…)'**
  String get vaultSecretField;

  /// No description provided for @vaultSiteField.
  ///
  /// In en, this message translates to:
  /// **'Site or app (optional)'**
  String get vaultSiteField;

  /// No description provided for @vaultUserField.
  ///
  /// In en, this message translates to:
  /// **'Username or email (optional)'**
  String get vaultUserField;

  /// No description provided for @vaultNotesField.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional — recovery codes, which branch, whom to call)'**
  String get vaultNotesField;

  /// No description provided for @vaultAddHint.
  ///
  /// In en, this message translates to:
  /// **'One entry per account. Record the site or app, the username you sign in with, and the secret itself — the person who will one day need this is not you, and a password with no site and no username helps nobody.'**
  String get vaultAddHint;

  /// No description provided for @vaultEncryptSave.
  ///
  /// In en, this message translates to:
  /// **'Encrypt & save'**
  String get vaultEncryptSave;

  /// No description provided for @vaultUnlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Vault is locked'**
  String get vaultUnlockTitle;

  /// No description provided for @vaultUnlockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Everything inside is encrypted on your device. Wasiati can never read it.'**
  String get vaultUnlockSubtitle;

  /// No description provided for @vaultFaceIdSnack.
  ///
  /// In en, this message translates to:
  /// **'Face ID unlock is enabled on your device at launch.'**
  String get vaultFaceIdSnack;

  /// No description provided for @vaultUnlockFaceId.
  ///
  /// In en, this message translates to:
  /// **'Unlock with Face ID'**
  String get vaultUnlockFaceId;

  /// No description provided for @vaultOr.
  ///
  /// In en, this message translates to:
  /// **'or passphrase'**
  String get vaultOr;

  /// No description provided for @vaultPassphraseHint.
  ///
  /// In en, this message translates to:
  /// **'Your vault passphrase'**
  String get vaultPassphraseHint;

  /// No description provided for @vaultUnlockPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get vaultUnlockPassphrase;

  /// No description provided for @vaultForgotWarn.
  ///
  /// In en, this message translates to:
  /// **'If you lose your passphrase and Face ID, this vault cannot be recovered — not even by us. That is the point.'**
  String get vaultForgotWarn;

  /// No description provided for @vaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get vaultTitle;

  /// No description provided for @vaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted on your device before it ever leaves. We store only ciphertext.'**
  String get vaultSubtitle;

  /// No description provided for @vaultUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get vaultUnlocked;

  /// No description provided for @vaultAutoLockIn.
  ///
  /// In en, this message translates to:
  /// **'Auto-locks in {n}s'**
  String vaultAutoLockIn(int n);

  /// No description provided for @vaultRevealFootnote.
  ///
  /// In en, this message translates to:
  /// **'Reveals hide automatically after 10 seconds.'**
  String get vaultRevealFootnote;

  /// No description provided for @vaultDecryptFailed.
  ///
  /// In en, this message translates to:
  /// **'This secret can’t be decrypted with the current passphrase. It may have been saved under a different one — lock the vault and try another passphrase.'**
  String get vaultDecryptFailed;

  /// No description provided for @vaultAddSecretBtn.
  ///
  /// In en, this message translates to:
  /// **'Add secret'**
  String get vaultAddSecretBtn;

  /// No description provided for @vaultLockNow.
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get vaultLockNow;

  /// No description provided for @vaultEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your vault is empty'**
  String get vaultEmptyTitle;

  /// No description provided for @vaultEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add a secret your family will need — a bank IBAN, a deed, a recovery phrase.'**
  String get vaultEmptySubtitle;

  /// No description provided for @vaultWarnCallout.
  ///
  /// In en, this message translates to:
  /// **'If you forget your passphrase, these secrets cannot be recovered — by us or anyone. Consider sharing a hint with your trustee.'**
  String get vaultWarnCallout;

  /// No description provided for @vaultUpgradeTitle.
  ///
  /// In en, this message translates to:
  /// **'The vault is part of Standard'**
  String get vaultUpgradeTitle;

  /// No description provided for @vaultUpgradeBody.
  ///
  /// In en, this message translates to:
  /// **'It keeps account numbers, deeds and passwords encrypted for your family.'**
  String get vaultUpgradeBody;

  /// No description provided for @dcRejectTitle.
  ///
  /// In en, this message translates to:
  /// **'Reject claim'**
  String get dcRejectTitle;

  /// No description provided for @dcReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get dcReason;

  /// No description provided for @dcRejectReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'A written reason is required to reject.'**
  String get dcRejectReasonRequired;

  /// No description provided for @dcReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get dcReject;

  /// No description provided for @dcEyebrow.
  ///
  /// In en, this message translates to:
  /// **'ADMIN — DEATH CLAIMS'**
  String get dcEyebrow;

  /// No description provided for @dcTitle.
  ///
  /// In en, this message translates to:
  /// **'Claims queue'**
  String get dcTitle;

  /// No description provided for @dcCareNote.
  ///
  /// In en, this message translates to:
  /// **'Human review, always. Rejection requires a reason. Release is a separate, logged action.'**
  String get dcCareNote;

  /// No description provided for @dcNoPending.
  ///
  /// In en, this message translates to:
  /// **'No pending claims.'**
  String get dcNoPending;

  /// No description provided for @dcSubmittedBy.
  ///
  /// In en, this message translates to:
  /// **'Submitted by {phone}'**
  String dcSubmittedBy(String phone);

  /// No description provided for @dcSubmittedByFor.
  ///
  /// In en, this message translates to:
  /// **'Submitted by {phone} · for {email}'**
  String dcSubmittedByFor(String phone, String email);

  /// No description provided for @dcCertificateOnFile.
  ///
  /// In en, this message translates to:
  /// **'Certificate on file'**
  String get dcCertificateOnFile;

  /// No description provided for @dcViewCertificate.
  ///
  /// In en, this message translates to:
  /// **'View certificate'**
  String get dcViewCertificate;

  /// No description provided for @dcCertificateOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'That certificate could not be opened. Do not approve this claim until you have seen it.'**
  String get dcCertificateOpenFailed;

  /// No description provided for @dcStartReview.
  ///
  /// In en, this message translates to:
  /// **'Start review'**
  String get dcStartReview;

  /// No description provided for @dcApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get dcApprove;

  /// No description provided for @dcRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get dcRelease;

  /// No description provided for @dcStatusSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get dcStatusSubmitted;

  /// No description provided for @dcStatusUnderReview.
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get dcStatusUnderReview;

  /// No description provided for @dcStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get dcStatusApproved;

  /// No description provided for @dcStatusReleased.
  ///
  /// In en, this message translates to:
  /// **'Released'**
  String get dcStatusReleased;

  /// No description provided for @dcStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get dcStatusRejected;

  /// No description provided for @navBurialQuotes.
  ///
  /// In en, this message translates to:
  /// **'Burial quotes'**
  String get navBurialQuotes;

  /// No description provided for @bqEyebrow.
  ///
  /// In en, this message translates to:
  /// **'ADMIN — BURIAL QUOTES'**
  String get bqEyebrow;

  /// No description provided for @bqTitle.
  ///
  /// In en, this message translates to:
  /// **'Quote requests'**
  String get bqTitle;

  /// No description provided for @bqCareNote.
  ///
  /// In en, this message translates to:
  /// **'A request means the client wants a real price. Call mosques and funeral homes in their city, then record the quote here — the client sees it on their Burial page.'**
  String get bqCareNote;

  /// No description provided for @bqNoPending.
  ///
  /// In en, this message translates to:
  /// **'No quote requests waiting.'**
  String get bqNoPending;

  /// No description provided for @bqRequestedBy.
  ///
  /// In en, this message translates to:
  /// **'Requested by {email}'**
  String bqRequestedBy(String email);

  /// No description provided for @bqEstimateLine.
  ///
  /// In en, this message translates to:
  /// **'Base {base} · projected {projected} over {years} yrs'**
  String bqEstimateLine(String base, String projected, int years);

  /// No description provided for @bqQuotedLine.
  ///
  /// In en, this message translates to:
  /// **'Quoted: {amount}'**
  String bqQuotedLine(String amount);

  /// No description provided for @bqStatusRequested.
  ///
  /// In en, this message translates to:
  /// **'Quote requested'**
  String get bqStatusRequested;

  /// No description provided for @bqStatusQuoted.
  ///
  /// In en, this message translates to:
  /// **'Quoted'**
  String get bqStatusQuoted;

  /// No description provided for @bqRecordQuote.
  ///
  /// In en, this message translates to:
  /// **'Record quote'**
  String get bqRecordQuote;

  /// No description provided for @bqQuoteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Record the sourced quote'**
  String get bqQuoteDialogTitle;

  /// No description provided for @bqAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String bqAmountLabel(String currency);

  /// No description provided for @bqNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get bqNotesLabel;

  /// No description provided for @bqNotesHelper.
  ///
  /// In en, this message translates to:
  /// **'e.g. which mosque quoted it and what it covers'**
  String get bqNotesHelper;

  /// No description provided for @bqErrorAmountRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the quoted amount.'**
  String get bqErrorAmountRequired;

  /// No description provided for @bqQuoteSaved.
  ///
  /// In en, this message translates to:
  /// **'Quote recorded — the client can now see it.'**
  String get bqQuoteSaved;

  /// No description provided for @auEyebrow.
  ///
  /// In en, this message translates to:
  /// **'ADMIN — USERS'**
  String get auEyebrow;

  /// No description provided for @auUsersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} users'**
  String auUsersCount(int count);

  /// No description provided for @auRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get auRefresh;

  /// No description provided for @auByRegion.
  ///
  /// In en, this message translates to:
  /// **'Users by region'**
  String get auByRegion;

  /// No description provided for @auIdVerification.
  ///
  /// In en, this message translates to:
  /// **'ID verification'**
  String get auIdVerification;

  /// No description provided for @auByRole.
  ///
  /// In en, this message translates to:
  /// **'By role'**
  String get auByRole;

  /// No description provided for @auNoData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get auNoData;

  /// No description provided for @auAllUsers.
  ///
  /// In en, this message translates to:
  /// **'All users'**
  String get auAllUsers;

  /// No description provided for @auColEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get auColEmail;

  /// No description provided for @auColPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get auColPhone;

  /// No description provided for @auColRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get auColRegion;

  /// No description provided for @auColRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get auColRole;

  /// No description provided for @auColId.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get auColId;

  /// No description provided for @auColEmailVerified.
  ///
  /// In en, this message translates to:
  /// **'Email verified'**
  String get auColEmailVerified;

  /// No description provided for @auColComp.
  ///
  /// In en, this message translates to:
  /// **'Comp'**
  String get auColComp;

  /// No description provided for @auColLastIp.
  ///
  /// In en, this message translates to:
  /// **'Last IP'**
  String get auColLastIp;

  /// No description provided for @auColJoined.
  ///
  /// In en, this message translates to:
  /// **'Joined'**
  String get auColJoined;

  /// No description provided for @auTitle.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get auTitle;

  /// No description provided for @auExportExcel.
  ///
  /// In en, this message translates to:
  /// **'Export to Excel'**
  String get auExportExcel;

  /// No description provided for @auStatTotalUsers.
  ///
  /// In en, this message translates to:
  /// **'TOTAL USERS'**
  String get auStatTotalUsers;

  /// No description provided for @auStatSealedWills.
  ///
  /// In en, this message translates to:
  /// **'SEALED WILLS'**
  String get auStatSealedWills;

  /// No description provided for @auStatIdVerified.
  ///
  /// In en, this message translates to:
  /// **'ID VERIFIED'**
  String get auStatIdVerified;

  /// No description provided for @auStatDeltaWeek.
  ///
  /// In en, this message translates to:
  /// **'+{count} this week'**
  String auStatDeltaWeek(int count);

  /// No description provided for @auStatInReview.
  ///
  /// In en, this message translates to:
  /// **'{pct}% in review'**
  String auStatInReview(int pct);

  /// No description provided for @auColUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get auColUser;

  /// No description provided for @auColPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get auColPlan;

  /// No description provided for @auColIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get auColIdentity;

  /// No description provided for @auPlanFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get auPlanFree;

  /// No description provided for @auPlanBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get auPlanBasic;

  /// No description provided for @auPlanStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get auPlanStandard;

  /// No description provided for @auPlanPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get auPlanPremium;

  /// No description provided for @auPlanUltimate.
  ///
  /// In en, this message translates to:
  /// **'Ultimate'**
  String get auPlanUltimate;

  /// No description provided for @auCompTitle.
  ///
  /// In en, this message translates to:
  /// **'Comped access'**
  String get auCompTitle;

  /// No description provided for @auCompBody.
  ///
  /// In en, this message translates to:
  /// **'Grant {email} a tier with no payment — investor demos, QA and support accounts run on this.'**
  String auCompBody(String email);

  /// No description provided for @auCompTierLabel.
  ///
  /// In en, this message translates to:
  /// **'Tier'**
  String get auCompTierLabel;

  /// No description provided for @auCompGrant.
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get auCompGrant;

  /// No description provided for @auCompRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke comp'**
  String get auCompRevoke;

  /// No description provided for @auCompGranted.
  ///
  /// In en, this message translates to:
  /// **'Comp granted.'**
  String get auCompGranted;

  /// No description provided for @auCompRevoked.
  ///
  /// In en, this message translates to:
  /// **'Comp revoked.'**
  String get auCompRevoked;

  /// No description provided for @auCompChip.
  ///
  /// In en, this message translates to:
  /// **'Comp · {tier}'**
  String auCompChip(String tier);

  /// No description provided for @prLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load pricing:'**
  String get prLoadError;

  /// No description provided for @prPlansFor.
  ///
  /// In en, this message translates to:
  /// **'Plans for {region}'**
  String prPlansFor(String region);

  /// No description provided for @prPricesIn.
  ///
  /// In en, this message translates to:
  /// **'Prices in {currency} · set by region · admin-editable at runtime'**
  String prPricesIn(String currency);

  /// No description provided for @prNoPlans.
  ///
  /// In en, this message translates to:
  /// **'No plans configured for this region yet.'**
  String get prNoPlans;

  /// No description provided for @prChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose {plan}'**
  String prChoose(String plan);

  /// No description provided for @prUltimateTitle.
  ///
  /// In en, this message translates to:
  /// **'Ultimate — burial & funeral planning'**
  String get prUltimateTitle;

  /// No description provided for @prNotInRegion.
  ///
  /// In en, this message translates to:
  /// **'NOT IN YOUR REGION'**
  String get prNotInRegion;

  /// No description provided for @prUltimateSub.
  ///
  /// In en, this message translates to:
  /// **'Prepaid burial contributions added to your subscription.'**
  String get prUltimateSub;

  /// No description provided for @prLearnMore.
  ///
  /// In en, this message translates to:
  /// **'Learn more'**
  String get prLearnMore;

  /// No description provided for @prAlreadySubscribed.
  ///
  /// In en, this message translates to:
  /// **'Already subscribed?'**
  String get prAlreadySubscribed;

  /// No description provided for @prBillingSub.
  ///
  /// In en, this message translates to:
  /// **'Invoices, payment method, cancel anytime.'**
  String get prBillingSub;

  /// No description provided for @prManageBilling.
  ///
  /// In en, this message translates to:
  /// **'Manage billing'**
  String get prManageBilling;

  /// No description provided for @prPromoTitle.
  ///
  /// In en, this message translates to:
  /// **'Promo code'**
  String get prPromoTitle;

  /// No description provided for @prPromoHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. RAMADAN30'**
  String get prPromoHint;

  /// No description provided for @prApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get prApply;

  /// No description provided for @prCouldNotCheck.
  ///
  /// In en, this message translates to:
  /// **'Could not check code.'**
  String get prCouldNotCheck;

  /// No description provided for @prCodeApplied.
  ///
  /// In en, this message translates to:
  /// **'Code applied'**
  String get prCodeApplied;

  /// No description provided for @prInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid code'**
  String get prInvalidCode;

  /// No description provided for @prGatedTitle.
  ///
  /// In en, this message translates to:
  /// **'The encrypted vault keeps account numbers, deeds and passwords safe for your family.'**
  String get prGatedTitle;

  /// No description provided for @prGatedSub.
  ///
  /// In en, this message translates to:
  /// **'It\'s part of Standard — shown here as a soft prompt, never a hard wall.'**
  String get prGatedSub;

  /// No description provided for @prUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get prUpgrade;

  /// No description provided for @prBillingMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get prBillingMonthly;

  /// No description provided for @prBillingAnnual.
  ///
  /// In en, this message translates to:
  /// **'Annual'**
  String get prBillingAnnual;

  /// No description provided for @prCycleOnce.
  ///
  /// In en, this message translates to:
  /// **'One-time'**
  String get prCycleOnce;

  /// No description provided for @prCycleYearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get prCycleYearly;

  /// No description provided for @prTwoMonthsFree.
  ///
  /// In en, this message translates to:
  /// **'2 months free'**
  String get prTwoMonthsFree;

  /// No description provided for @prOneTimeNote.
  ///
  /// In en, this message translates to:
  /// **'One-time: pay once, keep your will, vault and inventory for life. Updates and re-sealing included; burial contributions still require an active Ultimate subscription.'**
  String get prOneTimeNote;

  /// No description provided for @prPlansTitle.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get prPlansTitle;

  /// No description provided for @prPlansSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prices set automatically for your region — {region} · {currency}'**
  String prPlansSubtitle(String region, String currency);

  /// No description provided for @prCycleYearlySave.
  ///
  /// In en, this message translates to:
  /// **'SAVE 10%'**
  String get prCycleYearlySave;

  /// No description provided for @prMonthlyCommit.
  ///
  /// In en, this message translates to:
  /// **'All subscription plans carry a minimum one-year, non-refundable commitment. You can upgrade or downgrade between plans on monthly billing only. One-time and yearly options are billed up front.'**
  String get prMonthlyCommit;

  /// No description provided for @prNoUltimateNote.
  ///
  /// In en, this message translates to:
  /// **'Ultimate is not offered in {region} — burial carries no cost here, so there is nothing to pre-plan or finance. It appears automatically for members in the US and Canada.'**
  String prNoUltimateNote(String region);

  /// No description provided for @prChoosePlan.
  ///
  /// In en, this message translates to:
  /// **'Choose plan'**
  String get prChoosePlan;

  /// No description provided for @prMostPopular.
  ///
  /// In en, this message translates to:
  /// **'MOST POPULAR'**
  String get prMostPopular;

  /// No description provided for @prLiveLabel.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get prLiveLabel;

  /// No description provided for @aiFatal503.
  ///
  /// In en, this message translates to:
  /// **'AI intake isn\'t switched on for this server yet. You can still build your will by hand.'**
  String get aiFatal503;

  /// No description provided for @aiResumed.
  ///
  /// In en, this message translates to:
  /// **'Welcome back — your conversation continues where it left off.'**
  String get aiResumed;

  /// No description provided for @aiGuidedIntake.
  ///
  /// In en, this message translates to:
  /// **'GUIDED INTAKE'**
  String get aiGuidedIntake;

  /// No description provided for @aiPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get aiPremium;

  /// No description provided for @aiTalkThrough.
  ///
  /// In en, this message translates to:
  /// **'Let\'s talk it through'**
  String get aiTalkThrough;

  /// No description provided for @aiComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Type your answer…'**
  String get aiComposerHint;

  /// No description provided for @aiMicListen.
  ///
  /// In en, this message translates to:
  /// **'Speak to Ameen'**
  String get aiMicListen;

  /// No description provided for @aiMicStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get aiMicStop;

  /// No description provided for @aiMicListening.
  ///
  /// In en, this message translates to:
  /// **'Listening… speak now'**
  String get aiMicListening;

  /// No description provided for @aiCaptured.
  ///
  /// In en, this message translates to:
  /// **'WHAT I\'VE CAPTURED'**
  String get aiCaptured;

  /// No description provided for @aiHeirs.
  ///
  /// In en, this message translates to:
  /// **'Heirs'**
  String get aiHeirs;

  /// No description provided for @aiHeirsNone.
  ///
  /// In en, this message translates to:
  /// **'None yet — I\'ll list them here as we talk.'**
  String get aiHeirsNone;

  /// No description provided for @aiAssets.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get aiAssets;

  /// No description provided for @aiAssetsNone.
  ///
  /// In en, this message translates to:
  /// **'None yet.'**
  String get aiAssetsNone;

  /// No description provided for @aiReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready when you are'**
  String get aiReadyTitle;

  /// No description provided for @aiReadyBody.
  ///
  /// In en, this message translates to:
  /// **'I\'ll turn this into a proper will you can review, edit and seal.'**
  String get aiReadyBody;

  /// No description provided for @aiTurnIntoWill.
  ///
  /// In en, this message translates to:
  /// **'Turn this into a will'**
  String get aiTurnIntoWill;

  /// No description provided for @aiHintCard.
  ///
  /// In en, this message translates to:
  /// **'Nothing here is final. Everything you say becomes an editable draft — the Sharia shares are computed for you afterwards.'**
  String get aiHintCard;

  /// No description provided for @aiGatedBadge.
  ///
  /// In en, this message translates to:
  /// **'Premium feature'**
  String get aiGatedBadge;

  /// No description provided for @aiGatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Talk your will into being'**
  String get aiGatedTitle;

  /// No description provided for @aiGatedBody.
  ///
  /// In en, this message translates to:
  /// **'Guided intake lets you build your will by conversation instead of forms — describe your family and estate in your own words, and we structure it for you. It\'s part of Premium and Ultimate.'**
  String get aiGatedBody;

  /// No description provided for @aiBuildByHand.
  ///
  /// In en, this message translates to:
  /// **'Build a will by hand'**
  String get aiBuildByHand;

  /// No description provided for @prBillingCancelSub.
  ///
  /// In en, this message translates to:
  /// **'Cancel subscription'**
  String get prBillingCancelSub;

  /// No description provided for @prBillingResume.
  ///
  /// In en, this message translates to:
  /// **'Resume subscription'**
  String get prBillingResume;

  /// No description provided for @kycVerifyDocument.
  ///
  /// In en, this message translates to:
  /// **'Verify my identity'**
  String get kycVerifyDocument;

  /// No description provided for @kycUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Identity verification is being switched on. Nothing is needed from you yet.'**
  String get kycUnavailable;

  /// No description provided for @prPromoCheckoutNote.
  ///
  /// In en, this message translates to:
  /// **'Also works at Stripe.'**
  String get prPromoCheckoutNote;

  /// No description provided for @prUltimateRegionSub.
  ///
  /// In en, this message translates to:
  /// **'Available in Canada & US only.'**
  String get prUltimateRegionSub;

  /// No description provided for @relBaytAlMal.
  ///
  /// In en, this message translates to:
  /// **'Bayt al-mal (public treasury)'**
  String get relBaytAlMal;

  /// No description provided for @burialContributionPeriod.
  ///
  /// In en, this message translates to:
  /// **'Contribution period'**
  String get burialContributionPeriod;

  /// No description provided for @burialContributionSummary.
  ///
  /// In en, this message translates to:
  /// **'{months} equal contributions · total {cost} exactly — no interest, no profit.'**
  String burialContributionSummary(int months, String cost);

  /// No description provided for @burialTerms.
  ///
  /// In en, this message translates to:
  /// **'This is an estimate, not a payment plan. Nothing has been charged and no money is being held for you yet — prepayment is not available on your account, and we will ask before anything is ever taken. The figures show what a grave in this city costs today and what that would come to each month, so you can plan. When prepayment opens, your contributions would be your own money, held for you and refundable at any time.'**
  String get burialTerms;

  /// No description provided for @cwMadhhabMalikiShafii.
  ///
  /// In en, this message translates to:
  /// **'Mālikī / Shāfiʿī — classical view'**
  String get cwMadhhabMalikiShafii;

  /// No description provided for @refTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite a friend'**
  String get refTitle;

  /// No description provided for @refSubtitle.
  ///
  /// In en, this message translates to:
  /// **'They get 10% off. You earn 2.5% of their first year or one-time purchase.'**
  String get refSubtitle;

  /// No description provided for @refYourCode.
  ///
  /// In en, this message translates to:
  /// **'Your referral code'**
  String get refYourCode;

  /// No description provided for @refCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get refCopyLink;

  /// No description provided for @refCopied.
  ///
  /// In en, this message translates to:
  /// **'Share link copied'**
  String get refCopied;

  /// No description provided for @refInvited.
  ///
  /// In en, this message translates to:
  /// **'Invited'**
  String get refInvited;

  /// No description provided for @refRewarded.
  ///
  /// In en, this message translates to:
  /// **'Rewarded'**
  String get refRewarded;

  /// No description provided for @refCapped.
  ///
  /// In en, this message translates to:
  /// **'Capped'**
  String get refCapped;

  /// No description provided for @refCreditAvailable.
  ///
  /// In en, this message translates to:
  /// **'Credit available'**
  String get refCreditAvailable;

  /// No description provided for @refCreditHeld.
  ///
  /// In en, this message translates to:
  /// **'Held'**
  String get refCreditHeld;

  /// No description provided for @refCreditHeldNote.
  ///
  /// In en, this message translates to:
  /// **'Referral credit becomes spendable {days} days after your friend’s purchase — that covers the refund window.'**
  String refCreditHeldNote(int days);

  /// No description provided for @refEarnedThisYear.
  ///
  /// In en, this message translates to:
  /// **'Earned this year'**
  String get refEarnedThisYear;

  /// No description provided for @refYearlyCap.
  ///
  /// In en, this message translates to:
  /// **'of {cap} yearly cap'**
  String refYearlyCap(String cap);

  /// No description provided for @refHaveCode.
  ///
  /// In en, this message translates to:
  /// **'Have a referral code?'**
  String get refHaveCode;

  /// No description provided for @refEnterCode.
  ///
  /// In en, this message translates to:
  /// **'Enter code'**
  String get refEnterCode;

  /// No description provided for @refApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get refApply;

  /// No description provided for @refApplied.
  ///
  /// In en, this message translates to:
  /// **'Referral code applied.'**
  String get refApplied;

  /// No description provided for @refCodeChip.
  ///
  /// In en, this message translates to:
  /// **'Referral code {code} will be applied'**
  String refCodeChip(String code);

  /// No description provided for @refTerms.
  ///
  /// In en, this message translates to:
  /// **'Applies to annual and one-time plans only. Monthly plans do not qualify.'**
  String get refTerms;

  /// No description provided for @refLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load your referral details.'**
  String get refLoadError;

  /// No description provided for @refHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Credit history'**
  String get refHistoryTitle;

  /// No description provided for @refHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No credit activity yet.'**
  String get refHistoryEmpty;

  /// No description provided for @refHistoryError.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load your credit history.'**
  String get refHistoryError;

  /// No description provided for @refHistoryReasonReferral.
  ///
  /// In en, this message translates to:
  /// **'Referral reward'**
  String get refHistoryReasonReferral;

  /// No description provided for @refHistoryReasonPurchase.
  ///
  /// In en, this message translates to:
  /// **'Applied to a purchase'**
  String get refHistoryReasonPurchase;

  /// No description provided for @refHistoryReasonAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get refHistoryReasonAdjustment;

  /// No description provided for @refHistoryReasonRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get refHistoryReasonRefund;

  /// No description provided for @refHistorySpendable.
  ///
  /// In en, this message translates to:
  /// **'spendable {date}'**
  String refHistorySpendable(String date);

  /// No description provided for @navReferrals.
  ///
  /// In en, this message translates to:
  /// **'Invite a friend'**
  String get navReferrals;

  /// No description provided for @navZakat.
  ///
  /// In en, this message translates to:
  /// **'Zakat'**
  String get navZakat;

  /// Breadcrumb on the zakat screen returning to the assets page the user opened it from.
  ///
  /// In en, this message translates to:
  /// **'‹ Back to assets'**
  String get zakatBackToAssets;

  /// Breadcrumb on the zakat screen when it was opened directly (deep link), so there is no prior page to return to.
  ///
  /// In en, this message translates to:
  /// **'‹ Back to dashboard'**
  String get zakatBackToDashboard;

  /// No description provided for @zakatTitle.
  ///
  /// In en, this message translates to:
  /// **'Zakat estimate'**
  String get zakatTitle;

  /// No description provided for @zakatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'On your cash, bank balances, shares and gold.'**
  String get zakatSubtitle;

  /// No description provided for @zakatDue.
  ///
  /// In en, this message translates to:
  /// **'Zakat due'**
  String get zakatDue;

  /// No description provided for @zakatNoneDue.
  ///
  /// In en, this message translates to:
  /// **'No zakat due'**
  String get zakatNoneDue;

  /// No description provided for @zakatBelowNisab.
  ///
  /// In en, this message translates to:
  /// **'Your zakatable wealth is below the nisab of {nisab}.'**
  String zakatBelowNisab(String nisab);

  /// No description provided for @zakatBase.
  ///
  /// In en, this message translates to:
  /// **'Zakatable total'**
  String get zakatBase;

  /// No description provided for @zakatNisab.
  ///
  /// In en, this message translates to:
  /// **'Nisab (85g of gold)'**
  String get zakatNisab;

  /// No description provided for @zakatRate.
  ///
  /// In en, this message translates to:
  /// **'Rate — one quarter of one tenth (rubʿ al-ʿushr)'**
  String get zakatRate;

  /// No description provided for @zakatHawl.
  ///
  /// In en, this message translates to:
  /// **'Hawl date'**
  String get zakatHawl;

  /// No description provided for @zakatHawlNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get zakatHawlNotSet;

  /// No description provided for @zakatSetHawl.
  ///
  /// In en, this message translates to:
  /// **'Set hawl date'**
  String get zakatSetHawl;

  /// No description provided for @zakatHawlHijriOnly.
  ///
  /// In en, this message translates to:
  /// **'Hijri only — the day (1–30) and month of your zakat anniversary.'**
  String get zakatHawlHijriOnly;

  /// No description provided for @zakatHawlDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get zakatHawlDay;

  /// No description provided for @zakatHawlMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get zakatHawlMonth;

  /// No description provided for @zakatHawlSaved.
  ///
  /// In en, this message translates to:
  /// **'Hawl date saved'**
  String get zakatHawlSaved;

  /// No description provided for @zakatCryptoExcluded.
  ///
  /// In en, this message translates to:
  /// **'Crypto is not counted in the zakat base.'**
  String get zakatCryptoExcluded;

  /// No description provided for @zakatUnconverted.
  ///
  /// In en, this message translates to:
  /// **'{count} holding(s) in {currency} are not counted: we have no fixed exchange rate to your currency and will not guess one.'**
  String zakatUnconverted(int count, String currency);

  /// No description provided for @zakatPayNow.
  ///
  /// In en, this message translates to:
  /// **'Pay your zakah'**
  String get zakatPayNow;

  /// No description provided for @zakatDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'This estimate may not be calculated correctly for your situation and is not a religious ruling. It assumes shares are held for trading, excludes your home, vehicles and pension, ignores debts deductible against zakat, and uses an approximate nisab. Real estate held for trade, business inventory and other cases have their own rules — verify with a scholar or your local zakat authority before paying.'**
  String get zakatDisclaimer;

  /// No description provided for @zakatUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The zakat estimate is unavailable right now.'**
  String get zakatUnavailable;

  /// No description provided for @zakatBasisCash.
  ///
  /// In en, this message translates to:
  /// **'Cash on hand — zakatable in full.'**
  String get zakatBasisCash;

  /// No description provided for @zakatBasisBank.
  ///
  /// In en, this message translates to:
  /// **'Bank balances — treated as cash.'**
  String get zakatBasisBank;

  /// No description provided for @zakatBasisShares.
  ///
  /// In en, this message translates to:
  /// **'Shares — zakatable at their market value, held for trading.'**
  String get zakatBasisShares;

  /// No description provided for @zakatBasisGold.
  ///
  /// In en, this message translates to:
  /// **'Gold — zakatable by value.'**
  String get zakatBasisGold;

  /// No description provided for @checkinTitle.
  ///
  /// In en, this message translates to:
  /// **'Inactivity check-in'**
  String get checkinTitle;

  /// No description provided for @checkinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We will ask, now and then, whether you are still with us. Two unanswered reminders alert your trustee — nothing is released.'**
  String get checkinSubtitle;

  /// No description provided for @checkinEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable check-in'**
  String get checkinEnable;

  /// No description provided for @checkinFrequency.
  ///
  /// In en, this message translates to:
  /// **'How often'**
  String get checkinFrequency;

  /// No description provided for @checkinMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get checkinMonthly;

  /// No description provided for @checkinQuarterly.
  ///
  /// In en, this message translates to:
  /// **'Quarterly'**
  String get checkinQuarterly;

  /// No description provided for @checkinYearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get checkinYearly;

  /// No description provided for @checkinLoadError.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your latest check-in settings — showing defaults.'**
  String get checkinLoadError;

  /// No description provided for @checkinLastConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Last confirmed'**
  String get checkinLastConfirmed;

  /// No description provided for @checkinNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get checkinNever;

  /// No description provided for @checkinConfirmNow.
  ///
  /// In en, this message translates to:
  /// **'I am still here'**
  String get checkinConfirmNow;

  /// No description provided for @checkinConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Thank you. Your reminders have been reset.'**
  String get checkinConfirmed;

  /// No description provided for @checkinTrusteeAlerted.
  ///
  /// In en, this message translates to:
  /// **'Your trustee has been alerted that you missed your check-ins.'**
  String get checkinTrusteeAlerted;

  /// No description provided for @claimPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Who may report my death'**
  String get claimPolicyTitle;

  /// No description provided for @claimPolicyTrustee.
  ///
  /// In en, this message translates to:
  /// **'My trustee only'**
  String get claimPolicyTrustee;

  /// No description provided for @claimPolicyHeirs.
  ///
  /// In en, this message translates to:
  /// **'Heirs, with documents'**
  String get claimPolicyHeirs;

  /// No description provided for @claimPolicyBoth.
  ///
  /// In en, this message translates to:
  /// **'Either'**
  String get claimPolicyBoth;

  /// No description provided for @claimPolicySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get claimPolicySaved;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save that change.'**
  String get settingsSaveFailed;

  /// No description provided for @hijriMonth1.
  ///
  /// In en, this message translates to:
  /// **'Muharram'**
  String get hijriMonth1;

  /// No description provided for @hijriMonth2.
  ///
  /// In en, this message translates to:
  /// **'Safar'**
  String get hijriMonth2;

  /// No description provided for @hijriMonth3.
  ///
  /// In en, this message translates to:
  /// **'Rabiʿ I'**
  String get hijriMonth3;

  /// No description provided for @hijriMonth4.
  ///
  /// In en, this message translates to:
  /// **'Rabiʿ II'**
  String get hijriMonth4;

  /// No description provided for @hijriMonth5.
  ///
  /// In en, this message translates to:
  /// **'Jumada I'**
  String get hijriMonth5;

  /// No description provided for @hijriMonth6.
  ///
  /// In en, this message translates to:
  /// **'Jumada II'**
  String get hijriMonth6;

  /// No description provided for @hijriMonth7.
  ///
  /// In en, this message translates to:
  /// **'Rajab'**
  String get hijriMonth7;

  /// No description provided for @hijriMonth8.
  ///
  /// In en, this message translates to:
  /// **'Shaʿban'**
  String get hijriMonth8;

  /// No description provided for @hijriMonth9.
  ///
  /// In en, this message translates to:
  /// **'Ramadan'**
  String get hijriMonth9;

  /// No description provided for @hijriMonth10.
  ///
  /// In en, this message translates to:
  /// **'Shawwal'**
  String get hijriMonth10;

  /// No description provided for @hijriMonth11.
  ///
  /// In en, this message translates to:
  /// **'Dhu al-Qaʿdah'**
  String get hijriMonth11;

  /// No description provided for @hijriMonth12.
  ///
  /// In en, this message translates to:
  /// **'Dhu al-Hijjah'**
  String get hijriMonth12;

  /// No description provided for @zakatCatCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get zakatCatCash;

  /// No description provided for @zakatCatBank.
  ///
  /// In en, this message translates to:
  /// **'Bank balances'**
  String get zakatCatBank;

  /// No description provided for @zakatCatShares.
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get zakatCatShares;

  /// No description provided for @zakatCatGold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get zakatCatGold;

  /// No description provided for @assetKindCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get assetKindCash;

  /// No description provided for @assetKindShares.
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get assetKindShares;

  /// No description provided for @assetKindGold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get assetKindGold;

  /// No description provided for @assetKindCrypto.
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get assetKindCrypto;

  /// No description provided for @exportTitle.
  ///
  /// In en, this message translates to:
  /// **'Download your will'**
  String get exportTitle;

  /// No description provided for @exportFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get exportFormat;

  /// No description provided for @exportFormatTable.
  ///
  /// In en, this message translates to:
  /// **'Structured listing'**
  String get exportFormatTable;

  /// No description provided for @exportFormatTableSub.
  ///
  /// In en, this message translates to:
  /// **'Heirs, shares and bequests as tables.'**
  String get exportFormatTableSub;

  /// No description provided for @exportFormatEssay.
  ///
  /// In en, this message translates to:
  /// **'Narrative will'**
  String get exportFormatEssay;

  /// No description provided for @exportFormatEssaySub.
  ///
  /// In en, this message translates to:
  /// **'The same, written as a testamentary essay.'**
  String get exportFormatEssaySub;

  /// No description provided for @wpPreviewHead.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get wpPreviewHead;

  /// No description provided for @wpEstateFormat.
  ///
  /// In en, this message translates to:
  /// **'ESTATE FORMAT'**
  String get wpEstateFormat;

  /// No description provided for @wpFormatTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get wpFormatTable;

  /// No description provided for @wpFormatNarrative.
  ///
  /// In en, this message translates to:
  /// **'Narrative'**
  String get wpFormatNarrative;

  /// No description provided for @wpSharesAs.
  ///
  /// In en, this message translates to:
  /// **'SHARES AS'**
  String get wpSharesAs;

  /// No description provided for @wpSharesPercent.
  ///
  /// In en, this message translates to:
  /// **'%'**
  String get wpSharesPercent;

  /// No description provided for @wpSharesFraction.
  ///
  /// In en, this message translates to:
  /// **'Fraction'**
  String get wpSharesFraction;

  /// No description provided for @wpFormatHelp.
  ///
  /// In en, this message translates to:
  /// **'How your assets & loans read in the exported will — a listed table, or flowing will language written for you.'**
  String get wpFormatHelp;

  /// No description provided for @wpPreviewFailed.
  ///
  /// In en, this message translates to:
  /// **'The preview could not be rendered. Please try again.'**
  String get wpPreviewFailed;

  /// No description provided for @wpPreviewRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get wpPreviewRetry;

  /// No description provided for @exportLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get exportLanguage;

  /// No description provided for @exportLangEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get exportLangEnglish;

  /// No description provided for @exportLangArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get exportLangArabic;

  /// No description provided for @exportDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get exportDownload;

  /// No description provided for @adminContentTitle.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get adminContentTitle;

  /// No description provided for @adminContentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit user-facing strings. Changes publish live over the app’s built-in copy.'**
  String get adminContentSubtitle;

  /// No description provided for @adminContentKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get adminContentKey;

  /// No description provided for @adminContentEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get adminContentEn;

  /// No description provided for @adminContentAr.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get adminContentAr;

  /// No description provided for @adminContentNote.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get adminContentNote;

  /// No description provided for @adminContentPublished.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get adminContentPublished;

  /// No description provided for @adminContentDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get adminContentDraft;

  /// No description provided for @adminContentAdd.
  ///
  /// In en, this message translates to:
  /// **'Add string'**
  String get adminContentAdd;

  /// No description provided for @adminContentEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get adminContentEdit;

  /// No description provided for @adminContentSave.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get adminContentSave;

  /// No description provided for @adminContentRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove override'**
  String get adminContentRemove;

  /// No description provided for @adminContentRemoved.
  ///
  /// In en, this message translates to:
  /// **'Reverted to the built-in string.'**
  String get adminContentRemoved;

  /// No description provided for @adminContentSaved.
  ///
  /// In en, this message translates to:
  /// **'Published live.'**
  String get adminContentSaved;

  /// No description provided for @adminContentHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get adminContentHistory;

  /// No description provided for @adminContentEmpty.
  ///
  /// In en, this message translates to:
  /// **'No overrides yet. Add one to change a string without an app release.'**
  String get adminContentEmpty;

  /// No description provided for @adminContentBothRequired.
  ///
  /// In en, this message translates to:
  /// **'Both English and Arabic are required.'**
  String get adminContentBothRequired;

  /// No description provided for @adminContentEditedBy.
  ///
  /// In en, this message translates to:
  /// **'{who} · {when}'**
  String adminContentEditedBy(String who, String when);

  /// No description provided for @navAdminContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get navAdminContent;

  /// No description provided for @wsChooseTitle.
  ///
  /// In en, this message translates to:
  /// **'How would you like to write your will?'**
  String get wsChooseTitle;

  /// No description provided for @wsChooseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Both paths end at the same review — you confirm every detail before anything is sealed.'**
  String get wsChooseSubtitle;

  /// No description provided for @wsAmeenTitle.
  ///
  /// In en, this message translates to:
  /// **'Talk to Ameen'**
  String get wsAmeenTitle;

  /// No description provided for @wsAmeenSub.
  ///
  /// In en, this message translates to:
  /// **'Answer a few questions in plain words; Ameen drafts your will. Nothing is added without your confirmation.'**
  String get wsAmeenSub;

  /// No description provided for @wsAmeenBadge.
  ///
  /// In en, this message translates to:
  /// **'INCLUDED IN YOUR PLAN'**
  String get wsAmeenBadge;

  /// No description provided for @wsAmeenVerse.
  ///
  /// In en, this message translates to:
  /// **'Al-Ameen — the trustworthy — the name the Prophet ṣallā Allāhu ʿalayhi wa-sallam was known by'**
  String get wsAmeenVerse;

  /// No description provided for @wsFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Guided form'**
  String get wsFormTitle;

  /// No description provided for @wsFormSub.
  ///
  /// In en, this message translates to:
  /// **'Fill it in yourself, step by step, with a live view of the shares.'**
  String get wsFormSub;

  /// No description provided for @wsFormMeta.
  ///
  /// In en, this message translates to:
  /// **'≈ 5 minutes · autosaves as you go'**
  String get wsFormMeta;

  /// No description provided for @wsChooseNote.
  ///
  /// In en, this message translates to:
  /// **'You can switch anytime — Ameen\'s confirmed items appear in the form, and the form\'s answers are visible to Ameen.'**
  String get wsChooseNote;

  /// No description provided for @wsAmeenPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium feature'**
  String get wsAmeenPremium;

  /// No description provided for @vaultExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get vaultExport;

  /// No description provided for @vaultExportWarnTitle.
  ///
  /// In en, this message translates to:
  /// **'Export secrets as readable text?'**
  String get vaultExportWarnTitle;

  /// No description provided for @vaultExportWarnBody.
  ///
  /// In en, this message translates to:
  /// **'The file this creates is NOT encrypted — anyone who can read it holds every secret in this vault. Save it only somewhere as safe as the vault itself, such as a home safe or a bank deposit box, and delete the file once it has served its purpose.'**
  String get vaultExportWarnBody;

  /// No description provided for @vaultExportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Export as plain text'**
  String get vaultExportConfirm;

  /// No description provided for @vaultExportHeader.
  ///
  /// In en, this message translates to:
  /// **'Wasiati vault — exported {date}'**
  String vaultExportHeader(String date);

  /// No description provided for @vaultExportHeaderWarn.
  ///
  /// In en, this message translates to:
  /// **'This file is not encrypted. Anyone who can read it can read every secret below. Delete it after use.'**
  String get vaultExportHeaderWarn;

  /// No description provided for @vaultExportDone.
  ///
  /// In en, this message translates to:
  /// **'Exported {count} secrets to wasiati-vault.txt. Delete the file once it has served its purpose.'**
  String vaultExportDone(int count);

  /// No description provided for @vaultExportSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count} items could not be decrypted and were left out.'**
  String vaultExportSkipped(int count);

  /// No description provided for @vaultImport.
  ///
  /// In en, this message translates to:
  /// **'Import passwords'**
  String get vaultImport;

  /// No description provided for @vaultImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import from Chrome or Apple Passwords'**
  String get vaultImportTitle;

  /// No description provided for @vaultImportHow.
  ///
  /// In en, this message translates to:
  /// **'Export your passwords to a CSV, then paste its contents below. Everything is encrypted on this device before it is saved — the text you paste never leaves your device unencrypted.'**
  String get vaultImportHow;

  /// No description provided for @vaultImportPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste your exported CSV here'**
  String get vaultImportPaste;

  /// No description provided for @vaultImportPreview.
  ///
  /// In en, this message translates to:
  /// **'{count} passwords found'**
  String vaultImportPreview(int count);

  /// No description provided for @vaultImportNone.
  ///
  /// In en, this message translates to:
  /// **'No passwords found — is this a Chrome or Apple Passwords export?'**
  String get vaultImportNone;

  /// No description provided for @vaultImportSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count} rows skipped (no password).'**
  String vaultImportSkipped(int count);

  /// No description provided for @vaultImportRun.
  ///
  /// In en, this message translates to:
  /// **'Import {count}'**
  String vaultImportRun(int count);

  /// No description provided for @vaultImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get vaultImporting;

  /// No description provided for @vaultImportDone.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} passwords.'**
  String vaultImportDone(int count);

  /// No description provided for @vaultImportDeleteFile.
  ///
  /// In en, this message translates to:
  /// **'Now delete the exported CSV file from your device — it is not encrypted.'**
  String get vaultImportDeleteFile;

  /// No description provided for @vidTitle.
  ///
  /// In en, this message translates to:
  /// **'Video messages'**
  String get vidTitle;

  /// No description provided for @vidSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A recorded message for your family, released with your will. Encrypted; only you can see it until then.'**
  String get vidSubtitle;

  /// No description provided for @vidStorage.
  ///
  /// In en, this message translates to:
  /// **'{used} of {quota} used'**
  String vidStorage(String used, String quota);

  /// No description provided for @vidStorageFull.
  ///
  /// In en, this message translates to:
  /// **'Your 1 GB storage is full. Delete a video, or email us for a secure upload link.'**
  String get vidStorageFull;

  /// No description provided for @vidNone.
  ///
  /// In en, this message translates to:
  /// **'No videos yet.'**
  String get vidNone;

  /// No description provided for @vidAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a video'**
  String get vidAdd;

  /// No description provided for @vidUploadFile.
  ///
  /// In en, this message translates to:
  /// **'Upload a file'**
  String get vidUploadFile;

  /// No description provided for @vidRecord.
  ///
  /// In en, this message translates to:
  /// **'Record now'**
  String get vidRecord;

  /// No description provided for @vidRecordSoon.
  ///
  /// In en, this message translates to:
  /// **'Recording is coming soon — upload a file for now.'**
  String get vidRecordSoon;

  /// No description provided for @vidDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get vidDelete;

  /// No description provided for @vidDeleted.
  ///
  /// In en, this message translates to:
  /// **'Video deleted.'**
  String get vidDeleted;

  /// No description provided for @vidUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Video storage isn’t enabled yet.'**
  String get vidUnavailable;

  /// No description provided for @vidDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this video? This cannot be undone.'**
  String get vidDeleteConfirm;

  /// No description provided for @vidBadType.
  ///
  /// In en, this message translates to:
  /// **'Please choose an MP4, WEBM or MOV file.'**
  String get vidBadType;

  /// No description provided for @vidUploaded.
  ///
  /// In en, this message translates to:
  /// **'Video uploaded.'**
  String get vidUploaded;

  /// No description provided for @vidPlay.
  ///
  /// In en, this message translates to:
  /// **'Play video'**
  String get vidPlay;

  /// No description provided for @vidPlayError.
  ///
  /// In en, this message translates to:
  /// **'Could not open this video. Please try again.'**
  String get vidPlayError;

  /// No description provided for @vidScanPending.
  ///
  /// In en, this message translates to:
  /// **'This video is still being checked. Try again shortly.'**
  String get vidScanPending;

  /// No description provided for @vidScanFailed.
  ///
  /// In en, this message translates to:
  /// **'This video failed a security check and cannot be played.'**
  String get vidScanFailed;

  /// No description provided for @vrTitle.
  ///
  /// In en, this message translates to:
  /// **'Record a message'**
  String get vrTitle;

  /// No description provided for @vrStart.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get vrStart;

  /// No description provided for @vrStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get vrStop;

  /// Pauses a recording in progress, keeping what has been recorded.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get vrPause;

  /// No description provided for @vrResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get vrResume;

  /// No description provided for @vrPauseFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be paused. Your recording is still running.'**
  String get vrPauseFailed;

  /// No description provided for @vrTimeLeft.
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String vrTimeLeft(Object time);

  /// Shown when a recording hits the maximum length and is stopped automatically.
  ///
  /// In en, this message translates to:
  /// **'One hour reached — your recording is saved and ready to review.'**
  String get vrMaxLengthReached;

  /// No description provided for @vrRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get vrRetake;

  /// No description provided for @vrUse.
  ///
  /// In en, this message translates to:
  /// **'Use this video'**
  String get vrUse;

  /// No description provided for @vrPermission.
  ///
  /// In en, this message translates to:
  /// **'Camera and microphone access is needed to record.'**
  String get vrPermission;

  /// No description provided for @vrNoCamera.
  ///
  /// In en, this message translates to:
  /// **'No camera found on this device.'**
  String get vrNoCamera;

  /// No description provided for @vrBusy.
  ///
  /// In en, this message translates to:
  /// **'Your camera is in use by another app. Close it and try again.'**
  String get vrBusy;

  /// No description provided for @vrInsecure.
  ///
  /// In en, this message translates to:
  /// **'Recording needs a secure (https) connection.'**
  String get vrInsecure;

  /// No description provided for @vrUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This browser can\'t record video. Try Chrome, Edge or Safari — or upload a file instead.'**
  String get vrUnsupported;

  /// No description provided for @vrFailed.
  ///
  /// In en, this message translates to:
  /// **'Recording stopped unexpectedly. Please try again.'**
  String get vrFailed;

  /// No description provided for @vrTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That recording is too large to upload. Record a shorter message, or upload a file instead.'**
  String get vrTooLarge;

  /// No description provided for @vrRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get vrRecording;

  /// No description provided for @vrUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get vrUploading;

  /// No description provided for @authContinueGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get authContinueGoogle;

  /// No description provided for @authContinueApple.
  ///
  /// In en, this message translates to:
  /// **'Apple'**
  String get authContinueApple;

  /// No description provided for @authUsePasskey.
  ///
  /// In en, this message translates to:
  /// **'Continue with passkey'**
  String get authUsePasskey;

  /// No description provided for @authContinueNafath.
  ///
  /// In en, this message translates to:
  /// **'Continue with Nafath'**
  String get authContinueNafath;

  /// No description provided for @authContinueEmail.
  ///
  /// In en, this message translates to:
  /// **'Continue with email'**
  String get authContinueEmail;

  /// No description provided for @authRecommended.
  ///
  /// In en, this message translates to:
  /// **'RECOMMENDED'**
  String get authRecommended;

  /// No description provided for @authOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOr;

  /// Generic failure of the Google sign-in ceremony.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in did not complete. Please try again.'**
  String get authGoogleFailed;

  /// Google returned no id_token, which means a missing server client id.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in is not fully set up on this app yet. Please use another method.'**
  String get authGoogleMisconfigured;

  /// No description provided for @authMethodSoon.
  ///
  /// In en, this message translates to:
  /// **'This sign-in option isn’t enabled in this build yet — use email for now.'**
  String get authMethodSoon;

  /// No description provided for @authDetectedRegion.
  ///
  /// In en, this message translates to:
  /// **'Detected region: {info}'**
  String authDetectedRegion(String info);

  /// No description provided for @lndHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Don’t let two nights pass without a will!'**
  String get lndHeroTitle;

  /// No description provided for @lndHeroSub.
  ///
  /// In en, this message translates to:
  /// **'Honored in minutes — shares computed, secrets vaulted, your words delivered to the people you love.'**
  String get lndHeroSub;

  /// No description provided for @lndCtaStart.
  ///
  /// In en, this message translates to:
  /// **'Start my will'**
  String get lndCtaStart;

  /// No description provided for @lndCtaPlans.
  ///
  /// In en, this message translates to:
  /// **'See plans'**
  String get lndCtaPlans;

  /// No description provided for @lndWhyTitle.
  ///
  /// In en, this message translates to:
  /// **'Why Wasiati'**
  String get lndWhyTitle;

  /// No description provided for @lndWhy1t.
  ///
  /// In en, this message translates to:
  /// **'Your whole legacy, one place'**
  String get lndWhy1t;

  /// No description provided for @lndWhy1d.
  ///
  /// In en, this message translates to:
  /// **'Will, vault, zakat estimate, video messages and burial wishes — everything your family will need, kept together and always current.'**
  String get lndWhy1d;

  /// No description provided for @lndWhy2t.
  ///
  /// In en, this message translates to:
  /// **'Your language, your school of thought'**
  String get lndWhy2t;

  /// No description provided for @lndWhy2d.
  ///
  /// In en, this message translates to:
  /// **'Fully Arabic or English — down to the exported will. Shares follow the majority view of the scholars, or your own school: Hanafi, Maliki, Shafi’i or Hanbali.'**
  String get lndWhy2d;

  /// No description provided for @lndWhy3t.
  ///
  /// In en, this message translates to:
  /// **'It doesn’t stop at sealing'**
  String get lndWhy3t;

  /// No description provided for @lndWhy3d.
  ///
  /// In en, this message translates to:
  /// **'Gentle check-ins while you live; at claim time a human reviews the documents, then your will, vault and videos reach your heirs.'**
  String get lndWhy3d;

  /// No description provided for @lndWhy4t.
  ///
  /// In en, this message translates to:
  /// **'Minutes, not billable hours'**
  String get lndWhy4t;

  /// No description provided for @lndWhy4d.
  ///
  /// In en, this message translates to:
  /// **'Four guided steps, live shares as you type, sealed today — at a fraction of a lawyer’s fee, in Arabic or English, with Nafath sign-in.'**
  String get lndWhy4d;

  /// No description provided for @lndWhy5t.
  ///
  /// In en, this message translates to:
  /// **'Simple, by design'**
  String get lndWhy5t;

  /// No description provided for @lndWhy5d.
  ///
  /// In en, this message translates to:
  /// **'One plain question at a time — no legal jargon, no forms that feel like court. If it isn’t needed, you’re never asked.'**
  String get lndWhy5d;

  /// No description provided for @lndDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Wasiati is not a law firm, and its employees are not lawyers. Nothing on this site is intended to create a lawyer–client relationship, and your use of Wasiati does not and will not create one between you and Wasiati. Wasiati is not a substitute for the advice of a lawyer and does not give legal advice or legal recommendations of any kind. We provide a service that lets you answer a series of questions and complete your own will. For more information, see our Disclaimer & Terms of Use.'**
  String get lndDisclaimer;

  /// No description provided for @lndLegalLink.
  ///
  /// In en, this message translates to:
  /// **'Disclaimer & Terms of Use'**
  String get lndLegalLink;

  /// No description provided for @lndPrivacyLink.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get lndPrivacyLink;

  /// No description provided for @lndCopyright.
  ///
  /// In en, this message translates to:
  /// **'© 2026 Wasiati Inc.'**
  String get lndCopyright;

  /// No description provided for @prPerMonth.
  ///
  /// In en, this message translates to:
  /// **'/mo'**
  String get prPerMonth;

  /// No description provided for @prPerYear.
  ///
  /// In en, this message translates to:
  /// **'/yr'**
  String get prPerYear;

  /// No description provided for @prUltimateNotOneTime.
  ///
  /// In en, this message translates to:
  /// **'Ultimate is a subscription. Its burial pre-planning is funded by contributions over 3, 5 or 10 years, so it isn’t available as a one-time purchase — choose Monthly or Yearly to include it.'**
  String get prUltimateNotOneTime;

  /// No description provided for @billingTitle.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get billingTitle;

  /// No description provided for @billingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your plan, payment method and invoices.'**
  String get billingSubtitle;

  /// No description provided for @billingCurrentPlan.
  ///
  /// In en, this message translates to:
  /// **'CURRENT PLAN'**
  String get billingCurrentPlan;

  /// No description provided for @billingRenewsOn.
  ///
  /// In en, this message translates to:
  /// **'Renews {date} · {price}'**
  String billingRenewsOn(String date, String price);

  /// No description provided for @billingRenewsOnPlain.
  ///
  /// In en, this message translates to:
  /// **'Renews {date}'**
  String billingRenewsOnPlain(String date);

  /// No description provided for @billingEndsOn.
  ///
  /// In en, this message translates to:
  /// **'Access ends {date}'**
  String billingEndsOn(String date);

  /// No description provided for @billingCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling at period end — your will and vault stay yours.'**
  String get billingCancelling;

  /// No description provided for @billingPastDueLine.
  ///
  /// In en, this message translates to:
  /// **'Payment failed on {date}'**
  String billingPastDueLine(String date);

  /// No description provided for @billingPastDueHelp.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t charge your card and will retry. Update your card below to keep your plan — after several failed attempts it is cancelled.'**
  String get billingPastDueHelp;

  /// No description provided for @billingPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT METHOD'**
  String get billingPaymentMethod;

  /// No description provided for @billingChangeCard.
  ///
  /// In en, this message translates to:
  /// **'Change card'**
  String get billingChangeCard;

  /// No description provided for @billingCardOnFile.
  ///
  /// In en, this message translates to:
  /// **'Card on file'**
  String get billingCardOnFile;

  /// No description provided for @billingNoCard.
  ///
  /// In en, this message translates to:
  /// **'No card saved'**
  String get billingNoCard;

  /// No description provided for @billingCardUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Card management is unavailable on this environment.'**
  String get billingCardUnavailable;

  /// No description provided for @billingInvoices.
  ///
  /// In en, this message translates to:
  /// **'INVOICES'**
  String get billingInvoices;

  /// No description provided for @billingNoInvoices.
  ///
  /// In en, this message translates to:
  /// **'No invoices yet. Your receipts appear here after your first payment.'**
  String get billingNoInvoices;

  /// No description provided for @billingPaid.
  ///
  /// In en, this message translates to:
  /// **'PAID'**
  String get billingPaid;

  /// No description provided for @billingRefunded.
  ///
  /// In en, this message translates to:
  /// **'REFUNDED'**
  String get billingRefunded;

  /// No description provided for @billingCreditApplied.
  ///
  /// In en, this message translates to:
  /// **'{amount} paid from account credit'**
  String billingCreditApplied(String amount);

  /// No description provided for @billingProviderNote.
  ///
  /// In en, this message translates to:
  /// **'Payments and card data are handled by Stripe — Wasiati never stores your card.'**
  String get billingProviderNote;

  /// No description provided for @billingNoPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'You have no active subscription'**
  String get billingNoPlanTitle;

  /// No description provided for @billingNoPlanBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a plan to start. Your will and vault stay yours either way.'**
  String get billingNoPlanBody;

  /// No description provided for @billingSeePlans.
  ///
  /// In en, this message translates to:
  /// **'See plans'**
  String get billingSeePlans;

  /// No description provided for @billingInvoiceError.
  ///
  /// In en, this message translates to:
  /// **'Could not download that invoice.'**
  String get billingInvoiceError;

  /// No description provided for @billingCancelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel your subscription?'**
  String get billingCancelConfirmTitle;

  /// No description provided for @billingCancelConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Your access continues to the end of the period you have paid for. Your will and vault stay yours. Any burial contributions stop and are returned to you.'**
  String get billingCancelConfirmBody;

  /// No description provided for @billingCancelConfirmKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep my plan'**
  String get billingCancelConfirmKeep;

  /// No description provided for @billingCancelled.
  ///
  /// In en, this message translates to:
  /// **'Your subscription will end at the close of this period.'**
  String get billingCancelled;

  /// No description provided for @billingResumed.
  ///
  /// In en, this message translates to:
  /// **'Your subscription will continue.'**
  String get billingResumed;

  /// No description provided for @billingLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your billing details.'**
  String get billingLoadError;

  /// No description provided for @portalTitle.
  ///
  /// In en, this message translates to:
  /// **'Heir & trustee portal'**
  String get portalTitle;

  /// No description provided for @portalSub.
  ///
  /// In en, this message translates to:
  /// **'Read-only access for heirs and the trustee. It opens only after a human reviewer approves the claim and the will is released.'**
  String get portalSub;

  /// No description provided for @portalRoleHeir.
  ///
  /// In en, this message translates to:
  /// **'I am an heir'**
  String get portalRoleHeir;

  /// No description provided for @portalRoleTrustee.
  ///
  /// In en, this message translates to:
  /// **'I am the trustee'**
  String get portalRoleTrustee;

  /// No description provided for @portalEmailPh.
  ///
  /// In en, this message translates to:
  /// **'Email registered in the will'**
  String get portalEmailPh;

  /// No description provided for @portalContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get portalContinue;

  /// No description provided for @portalCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm it\'s you'**
  String get portalCodeTitle;

  /// No description provided for @portalCodeSub.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code sent to your registered mobile.'**
  String get portalCodeSub;

  /// No description provided for @portalCodeSubEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code sent to your registered email address.'**
  String get portalCodeSubEmail;

  /// No description provided for @portalCodeResendWait.
  ///
  /// In en, this message translates to:
  /// **'You can ask for another code in {seconds}s'**
  String portalCodeResendWait(int seconds);

  /// No description provided for @portalCodeResendReady.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t get it?'**
  String get portalCodeResendReady;

  /// No description provided for @portalCodeResend.
  ///
  /// In en, this message translates to:
  /// **'Send another code'**
  String get portalCodeResend;

  /// No description provided for @portalChipHeir.
  ///
  /// In en, this message translates to:
  /// **'HEIR'**
  String get portalChipHeir;

  /// No description provided for @portalChipTrustee.
  ///
  /// In en, this message translates to:
  /// **'TRUSTEE'**
  String get portalChipTrustee;

  /// No description provided for @portalReadOnly.
  ///
  /// In en, this message translates to:
  /// **'READ-ONLY'**
  String get portalReadOnly;

  /// No description provided for @portalSignOut.
  ///
  /// In en, this message translates to:
  /// **'Exit portal'**
  String get portalSignOut;

  /// No description provided for @portalPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Claim under review'**
  String get portalPendingTitle;

  /// No description provided for @portalPendingSub.
  ///
  /// In en, this message translates to:
  /// **'A human reviewer is checking the documents. Access opens the moment the claim is approved and released — we\'ll notify you.'**
  String get portalPendingSub;

  /// No description provided for @portalApprovedTitle.
  ///
  /// In en, this message translates to:
  /// **'Approved — awaiting release'**
  String get portalApprovedTitle;

  /// No description provided for @portalApprovedSub.
  ///
  /// In en, this message translates to:
  /// **'The claim was approved. The will is released once every registered heir confirms — or the trustee overrides.'**
  String get portalApprovedSub;

  /// No description provided for @heirApprovalsTitle.
  ///
  /// In en, this message translates to:
  /// **'HEIR RELEASE CONFIRMATIONS'**
  String get heirApprovalsTitle;

  /// No description provided for @heirConfirmBtn.
  ///
  /// In en, this message translates to:
  /// **'Confirm release of the will'**
  String get heirConfirmBtn;

  /// No description provided for @heirConfirmedNote.
  ///
  /// In en, this message translates to:
  /// **'Your confirmation is recorded'**
  String get heirConfirmedNote;

  /// No description provided for @portalWaitOthers.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the remaining confirmations — or a trustee override.'**
  String get portalWaitOthers;

  /// No description provided for @trusteeOverrideBtn.
  ///
  /// In en, this message translates to:
  /// **'Override — release without full confirmations'**
  String get trusteeOverrideBtn;

  /// No description provided for @overrideOnNote.
  ///
  /// In en, this message translates to:
  /// **'Trustee override recorded — release is unlocked.'**
  String get overrideOnNote;

  /// No description provided for @portalConfirmedMark.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get portalConfirmedMark;

  /// No description provided for @portalAwaitingMark.
  ///
  /// In en, this message translates to:
  /// **'Awaiting'**
  String get portalAwaitingMark;

  /// No description provided for @portalRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'This claim was not approved'**
  String get portalRejectedTitle;

  /// No description provided for @portalRejectedSub.
  ///
  /// In en, this message translates to:
  /// **'A reviewer could not approve the claim from the documents provided. If you believe this is a mistake, reply to the message we sent you and we will look again.'**
  String get portalRejectedSub;

  /// No description provided for @portalIstirjaa.
  ///
  /// In en, this message translates to:
  /// **'إِنَّا لِلَّهِ وَإِنَّا إِلَيْهِ رَاجِعُونَ'**
  String get portalIstirjaa;

  /// No description provided for @heirTitle.
  ///
  /// In en, this message translates to:
  /// **'The will of {estateName} has been released to you'**
  String heirTitle(String estateName);

  /// No description provided for @heirSub.
  ///
  /// In en, this message translates to:
  /// **'The claim was verified and approved. Everything below is now yours to see — take your time.'**
  String get heirSub;

  /// No description provided for @wordsTitle.
  ///
  /// In en, this message translates to:
  /// **'WORDS FOR MY FAMILY'**
  String get wordsTitle;

  /// No description provided for @heirSharesTitle.
  ///
  /// In en, this message translates to:
  /// **'DIVISION OF THE ESTATE'**
  String get heirSharesTitle;

  /// No description provided for @heirBequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'BEQUESTS'**
  String get heirBequestsTitle;

  /// No description provided for @heirVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'A video message for you'**
  String get heirVideoTitle;

  /// No description provided for @heirVideoMeta.
  ///
  /// In en, this message translates to:
  /// **'Recorded {date}'**
  String heirVideoMeta(String date);

  /// No description provided for @heirVideoOpen.
  ///
  /// In en, this message translates to:
  /// **'Play the video message'**
  String get heirVideoOpen;

  /// No description provided for @heirNoWords.
  ///
  /// In en, this message translates to:
  /// **'No written message was left on this will.'**
  String get heirNoWords;

  /// No description provided for @portalDebtsNote.
  ///
  /// In en, this message translates to:
  /// **'Debts are settled before shares are distributed.'**
  String get portalDebtsNote;

  /// No description provided for @portalLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load this will. Please use the link we sent you.'**
  String get portalLoadError;

  /// No description provided for @portalReportDeath.
  ///
  /// In en, this message translates to:
  /// **'I need to report a death'**
  String get portalReportDeath;

  /// No description provided for @pcLookupTitle.
  ///
  /// In en, this message translates to:
  /// **'Report a death'**
  String get pcLookupTitle;

  /// No description provided for @pcLookupSub.
  ///
  /// In en, this message translates to:
  /// **'If someone you know has died and you believe they left a will with us, tell us how to find them. We will contact the people named on the will directly — we cannot tell you whether a will exists.'**
  String get pcLookupSub;

  /// No description provided for @pcDeceasedLbl.
  ///
  /// In en, this message translates to:
  /// **'THE PERSON WHO HAS DIED'**
  String get pcDeceasedLbl;

  /// No description provided for @pcDeceasedPh.
  ///
  /// In en, this message translates to:
  /// **'Their email address or mobile number'**
  String get pcDeceasedPh;

  /// No description provided for @pcClaimantLbl.
  ///
  /// In en, this message translates to:
  /// **'YOU'**
  String get pcClaimantLbl;

  /// No description provided for @pcClaimantPh.
  ///
  /// In en, this message translates to:
  /// **'Your own email address or mobile number'**
  String get pcClaimantPh;

  /// No description provided for @pcLookupBtn.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get pcLookupBtn;

  /// No description provided for @pcAckTitle.
  ///
  /// In en, this message translates to:
  /// **'Thank you'**
  String get pcAckTitle;

  /// No description provided for @pcAckBody.
  ///
  /// In en, this message translates to:
  /// **'If a will exists, we\'ve notified the people named on it. Anyone named will receive a message with a link to continue. Nothing else is needed from you now.'**
  String get pcAckBody;

  /// No description provided for @pcAckClose.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get pcAckClose;

  /// No description provided for @pcInviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Begin the release of a will'**
  String get pcInviteTitle;

  /// No description provided for @pcInviteSub.
  ///
  /// In en, this message translates to:
  /// **'You are named on a will held with us, and someone has asked us to begin the process of releasing it. Take your time — nothing is released until a person here has reviewed it.'**
  String get pcInviteSub;

  /// No description provided for @pcNameLbl.
  ///
  /// In en, this message translates to:
  /// **'YOUR FULL NAME'**
  String get pcNameLbl;

  /// No description provided for @pcNamePh.
  ///
  /// In en, this message translates to:
  /// **'Your full legal name'**
  String get pcNamePh;

  /// No description provided for @pcCertTitle.
  ///
  /// In en, this message translates to:
  /// **'Death certificate'**
  String get pcCertTitle;

  /// No description provided for @pcCertSub.
  ///
  /// In en, this message translates to:
  /// **'A photograph or scan of the death certificate. A reviewer checks it by hand; nothing is released automatically.'**
  String get pcCertSub;

  /// No description provided for @pcCertChoose.
  ///
  /// In en, this message translates to:
  /// **'Attach the certificate'**
  String get pcCertChoose;

  /// No description provided for @pcCertUploading.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get pcCertUploading;

  /// No description provided for @pcCertAttached.
  ///
  /// In en, this message translates to:
  /// **'{fileName} attached'**
  String pcCertAttached(String fileName);

  /// No description provided for @pcCertRequired.
  ///
  /// In en, this message translates to:
  /// **'The certificate is needed before this can be sent.'**
  String get pcCertRequired;

  /// No description provided for @pcCertTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That file is larger than {size}. Please attach a smaller photograph or scan.'**
  String pcCertTooLarge(String size);

  /// No description provided for @pcCertBadType.
  ///
  /// In en, this message translates to:
  /// **'That file type cannot be accepted. Please attach a PDF or a photograph.'**
  String get pcCertBadType;

  /// No description provided for @pcCertOnce.
  ///
  /// In en, this message translates to:
  /// **'This link carries one certificate. If this is the wrong file, reply to the message we sent you and we will send a fresh link.'**
  String get pcCertOnce;

  /// No description provided for @pcSubmitBtn.
  ///
  /// In en, this message translates to:
  /// **'Send for review'**
  String get pcSubmitBtn;

  /// No description provided for @pcDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'We have it'**
  String get pcDoneTitle;

  /// No description provided for @pcDoneSub.
  ///
  /// In en, this message translates to:
  /// **'A reviewer will look at the certificate by hand. We will write to you when there is news — you do not need to do anything else. May Allah ease this for you.'**
  String get pcDoneSub;

  /// No description provided for @pcLinkInvalidTitle.
  ///
  /// In en, this message translates to:
  /// **'This link is no longer valid'**
  String get pcLinkInvalidTitle;

  /// No description provided for @pcLinkInvalidSub.
  ///
  /// In en, this message translates to:
  /// **'The link may have expired or already been used. If you still need to report a death, you can start again.'**
  String get pcLinkInvalidSub;

  /// No description provided for @pcStartOver.
  ///
  /// In en, this message translates to:
  /// **'Start again'**
  String get pcStartOver;

  /// No description provided for @burialEstimateOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'Estimate only — no payment has been set up.'**
  String get burialEstimateOnlyNote;

  /// No description provided for @tcTitle.
  ///
  /// In en, this message translates to:
  /// **'You have been named a trustee'**
  String get tcTitle;

  /// No description provided for @tcSub.
  ///
  /// In en, this message translates to:
  /// **'Assalamu alaikum. The owner of a will held with Wasiati has asked you to be its trustee.'**
  String get tcSub;

  /// No description provided for @tcDuties.
  ///
  /// In en, this message translates to:
  /// **'As trustee you would: confirm their passing to Wasiati, start the claim with the death certificate, and see the will released to their heirs. You never see the will\'s contents while they are alive.'**
  String get tcDuties;

  /// No description provided for @tcAcceptBtn.
  ///
  /// In en, this message translates to:
  /// **'Accept the role'**
  String get tcAcceptBtn;

  /// No description provided for @tcDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get tcDecline;

  /// No description provided for @tcCodeSub.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code we sent to the mobile number on the will.'**
  String get tcCodeSub;

  /// No description provided for @tcDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'You are now the trustee'**
  String get tcDoneTitle;

  /// No description provided for @tcDoneSub.
  ///
  /// In en, this message translates to:
  /// **'May you never be needed. We\'ll only contact you for annual confirmation — and, one day, for the claim.'**
  String get tcDoneSub;

  /// No description provided for @wcTitle.
  ///
  /// In en, this message translates to:
  /// **'You have been asked to witness a will'**
  String get wcTitle;

  /// No description provided for @wcSub.
  ///
  /// In en, this message translates to:
  /// **'Assalamu alaikum. The owner of a will held with Wasiati has named you as one of its witnesses.'**
  String get wcSub;

  /// No description provided for @wcDuties.
  ///
  /// In en, this message translates to:
  /// **'As a witness you confirm, under your legal name, that the owner declared this to be their will, made freely. You do not see the will\'s contents — only that it was made.'**
  String get wcDuties;

  /// No description provided for @wcLegalNameLbl.
  ///
  /// In en, this message translates to:
  /// **'Your legal name'**
  String get wcLegalNameLbl;

  /// No description provided for @wcLegalNamePh.
  ///
  /// In en, this message translates to:
  /// **'Exactly as on your ID'**
  String get wcLegalNamePh;

  /// No description provided for @wcLegalNameHelp.
  ///
  /// In en, this message translates to:
  /// **'It must match the name the owner put on the will, or the signature will not be recorded.'**
  String get wcLegalNameHelp;

  /// No description provided for @wcSignBtn.
  ///
  /// In en, this message translates to:
  /// **'Continue to sign'**
  String get wcSignBtn;

  /// No description provided for @wcCodeSub.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code we sent to the mobile number on the will. Entering it records your witness signature.'**
  String get wcCodeSub;

  /// No description provided for @wcDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Your witness signature is recorded'**
  String get wcDoneTitle;

  /// No description provided for @wcDoneSub.
  ///
  /// In en, this message translates to:
  /// **'JazakAllahu khairan — your part is done. Nothing more is needed from you.'**
  String get wcDoneSub;

  /// No description provided for @confirmClosePage.
  ///
  /// In en, this message translates to:
  /// **'You can close this page.'**
  String get confirmClosePage;

  /// No description provided for @confirmDeclinedTitle.
  ///
  /// In en, this message translates to:
  /// **'No action was taken'**
  String get confirmDeclinedTitle;

  /// No description provided for @confirmDeclinedSub.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been recorded or sent. If you change your mind, open the link from the SMS again.'**
  String get confirmDeclinedSub;

  /// No description provided for @confirmLinkInvalidTitle.
  ///
  /// In en, this message translates to:
  /// **'This link is no longer valid'**
  String get confirmLinkInvalidTitle;

  /// No description provided for @confirmLinkInvalidSub.
  ///
  /// In en, this message translates to:
  /// **'The link may be incomplete, or the invitation may have been withdrawn. Please contact the person who named you.'**
  String get confirmLinkInvalidSub;

  /// No description provided for @portalWillPdfTitle.
  ///
  /// In en, this message translates to:
  /// **'THE WILL ITSELF'**
  String get portalWillPdfTitle;

  /// No description provided for @portalWillPdfSub.
  ///
  /// In en, this message translates to:
  /// **'The executed will, as it was sealed. Keep a copy — you may need it for a court, a bank or a land registry.'**
  String get portalWillPdfSub;

  /// No description provided for @portalWillPdfDownload.
  ///
  /// In en, this message translates to:
  /// **'Download the will (PDF)'**
  String get portalWillPdfDownload;

  /// No description provided for @passkeyErrorUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This browser doesn’t support passkeys. Use another sign-in method.'**
  String get passkeyErrorUnsupported;

  /// No description provided for @passkeyErrorCancelled.
  ///
  /// In en, this message translates to:
  /// **'Passkey sign-in was cancelled — or this device has no passkey for Wasiati yet. You can add one in Settings after signing in.'**
  String get passkeyErrorCancelled;

  /// No description provided for @passkeyErrorRegisterCancelled.
  ///
  /// In en, this message translates to:
  /// **'Passkey setup was cancelled before it finished. Nothing was saved.'**
  String get passkeyErrorRegisterCancelled;

  /// No description provided for @passkeyErrorAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'This device already holds a passkey for your account — you can sign in with it now.'**
  String get passkeyErrorAlreadyRegistered;

  /// No description provided for @passkeyErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'The passkey attempt didn’t complete. Try again, or use another sign-in method.'**
  String get passkeyErrorGeneric;

  /// No description provided for @settingsAddPasskey.
  ///
  /// In en, this message translates to:
  /// **'Add a passkey'**
  String get settingsAddPasskey;

  /// No description provided for @settingsAddPasskeySub.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your face, fingerprint or device PIN — no code needed'**
  String get settingsAddPasskeySub;

  /// Title of the post-signup passkey enrolment screen.
  ///
  /// In en, this message translates to:
  /// **'Sign in without a code'**
  String get pkSetupTitle;

  /// No description provided for @pkSetupBlurb.
  ///
  /// In en, this message translates to:
  /// **'One more step, and it saves you every time after'**
  String get pkSetupBlurb;

  /// No description provided for @pkSetupWhy.
  ///
  /// In en, this message translates to:
  /// **'Use Face ID, Touch ID or Windows Hello to sign in. No text message, nothing to wait for — and it cannot be phished.'**
  String get pkSetupWhy;

  /// No description provided for @pkSetupCta.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get pkSetupCta;

  /// No description provided for @pkSetupSkip.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get pkSetupSkip;

  /// No description provided for @pkSetupLater.
  ///
  /// In en, this message translates to:
  /// **'Your password still works, and you can set this up any time in Settings.'**
  String get pkSetupLater;

  /// No description provided for @passkeyAdded.
  ///
  /// In en, this message translates to:
  /// **'Passkey added — you can now use it to sign in on this device.'**
  String get passkeyAdded;

  /// No description provided for @mfaResendSent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way.'**
  String get mfaResendSent;

  /// No description provided for @adminContentKeyHelp.
  ///
  /// In en, this message translates to:
  /// **'Only strings the app can actually show are listed.'**
  String get adminContentKeyHelp;

  /// No description provided for @wdContinueDraft.
  ///
  /// In en, this message translates to:
  /// **'Continue your draft'**
  String get wdContinueDraft;

  /// Back link from the video recorder to the list of family messages.
  ///
  /// In en, this message translates to:
  /// **'Messages to my family'**
  String get commonBackToLegacy;

  /// Forward button on the last guided step; leaves the wizard for the Review & seal page.
  ///
  /// In en, this message translates to:
  /// **'Continue to review'**
  String get cwToReview;

  /// Review section heading for the guardian named for minor children.
  ///
  /// In en, this message translates to:
  /// **'Guardianship'**
  String get rsGuardianTitle;

  /// Title of the dedicated will-document page.
  ///
  /// In en, this message translates to:
  /// **'Your will, as it will be read'**
  String get wdocTitle;

  /// Subtitle of the will-document page, explaining it is the real file.
  ///
  /// In en, this message translates to:
  /// **'The document itself — the same file the download produces. Choose how it reads below.'**
  String get wdocSubtitle;

  /// Button on the will detail header that opens the document page.
  ///
  /// In en, this message translates to:
  /// **'View document'**
  String get wdViewDocument;

  /// Callout on the will-document page explaining how the document gets signed.
  ///
  /// In en, this message translates to:
  /// **'You sign by confirming below; your two witnesses and your trustee then confirm by SMS. Nothing is released until all three have.'**
  String get wdocSigningNote;

  /// Will document header: the testator, e.g. 'of Ahmed Al-Rashid'.
  ///
  /// In en, this message translates to:
  /// **'of {name}'**
  String wdocOf(Object name);

  /// Will document header/footer: the short will identifier.
  ///
  /// In en, this message translates to:
  /// **'Will #{id}'**
  String wdocWillNumber(Object id);

  /// Will document meta line: the seal date.
  ///
  /// In en, this message translates to:
  /// **'sealed {date}'**
  String wdocSealedMeta(Object date);

  /// Will document meta line: how many witnesses have confirmed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 witness confirmed} other{{count} witnesses confirmed}}'**
  String wdocWitnessesConfirmed(int count);

  /// No description provided for @wdocDraftSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Draft — not yet sealed'**
  String get wdocDraftSubtitle;

  /// No description provided for @wdocWordsTitle.
  ///
  /// In en, this message translates to:
  /// **'Words for my family'**
  String get wdocWordsTitle;

  /// No description provided for @wdocWishesTitle.
  ///
  /// In en, this message translates to:
  /// **'Funeral & burial wishes'**
  String get wdocWishesTitle;

  /// No description provided for @wdocEstateTitle.
  ///
  /// In en, this message translates to:
  /// **'Assets & liabilities'**
  String get wdocEstateTitle;

  /// No description provided for @wdocNetEstate.
  ///
  /// In en, this message translates to:
  /// **'Net estate'**
  String get wdocNetEstate;

  /// No description provided for @wdocEstateNote.
  ///
  /// In en, this message translates to:
  /// **'Estate inventory as recorded at sealing; debts are settled before the shares are distributed.'**
  String get wdocEstateNote;

  /// No description provided for @wdocEssayAssetsLead.
  ///
  /// In en, this message translates to:
  /// **'I declare that, as of the sealing of this will, I own the following assets: '**
  String get wdocEssayAssetsLead;

  /// No description provided for @wdocEssayLiabilitiesLead.
  ///
  /// In en, this message translates to:
  /// **'I further declare the following debts and obligations, to be settled from my estate before any distribution: '**
  String get wdocEssayLiabilitiesLead;

  /// No description provided for @wdocEssayHeldWith.
  ///
  /// In en, this message translates to:
  /// **', held with {institution}'**
  String wdocEssayHeldWith(Object institution);

  /// No description provided for @wdocEssayValuedAt.
  ///
  /// In en, this message translates to:
  /// **', valued at approximately {amount}'**
  String wdocEssayValuedAt(Object amount);

  /// No description provided for @wdocEssayOwedTo.
  ///
  /// In en, this message translates to:
  /// **', owed to {institution}'**
  String wdocEssayOwedTo(Object institution);

  /// No description provided for @wdocEssayInAmount.
  ///
  /// In en, this message translates to:
  /// **', in the amount of {amount}'**
  String wdocEssayInAmount(Object amount);

  /// No description provided for @wdocEssayNetEstate.
  ///
  /// In en, this message translates to:
  /// **'After settlement of these obligations, my net estate today amounts to approximately {amount}.'**
  String wdocEssayNetEstate(Object amount);

  /// No description provided for @wdocEssayListJoin.
  ///
  /// In en, this message translates to:
  /// **'; '**
  String get wdocEssayListJoin;

  /// No description provided for @wdocEssayListJoinLast.
  ///
  /// In en, this message translates to:
  /// **'; and '**
  String get wdocEssayListJoinLast;

  /// No description provided for @wdocEssayNetJoin.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get wdocEssayNetJoin;

  /// No description provided for @wdocDivisionTitle.
  ///
  /// In en, this message translates to:
  /// **'Division of the estate'**
  String get wdocDivisionTitle;

  /// No description provided for @wdocNoHeirs.
  ///
  /// In en, this message translates to:
  /// **'No heirs recorded.'**
  String get wdocNoHeirs;

  /// No description provided for @wdocBequest.
  ///
  /// In en, this message translates to:
  /// **'Bequest'**
  String get wdocBequest;

  /// No description provided for @wdocBequestBasis.
  ///
  /// In en, this message translates to:
  /// **'From the free third — outside the fara’id'**
  String get wdocBequestBasis;

  /// No description provided for @wdocWitnessesTitle.
  ///
  /// In en, this message translates to:
  /// **'Witnesses & trustee'**
  String get wdocWitnessesTitle;

  /// No description provided for @wdocWitnessesCol.
  ///
  /// In en, this message translates to:
  /// **'Witnesses'**
  String get wdocWitnessesCol;

  /// No description provided for @wdocTrusteeCol.
  ///
  /// In en, this message translates to:
  /// **'Trustee'**
  String get wdocTrusteeCol;

  /// No description provided for @wdocWitnessRole.
  ///
  /// In en, this message translates to:
  /// **'Witness'**
  String get wdocWitnessRole;

  /// No description provided for @wdocTrusteeRole.
  ///
  /// In en, this message translates to:
  /// **'Trustee'**
  String get wdocTrusteeRole;

  /// No description provided for @wdocTestatorRole.
  ///
  /// In en, this message translates to:
  /// **'Testator'**
  String get wdocTestatorRole;

  /// No description provided for @wdocSignedDigitally.
  ///
  /// In en, this message translates to:
  /// **'Signed digitally'**
  String get wdocSignedDigitally;

  /// No description provided for @wdocPending.
  ///
  /// In en, this message translates to:
  /// **'pending'**
  String get wdocPending;

  /// No description provided for @wdocPendingCode.
  ///
  /// In en, this message translates to:
  /// **'pending code'**
  String get wdocPendingCode;

  /// No description provided for @wdocNoneRecorded.
  ///
  /// In en, this message translates to:
  /// **'None recorded.'**
  String get wdocNoneRecorded;

  /// No description provided for @wdocSealLine.
  ///
  /// In en, this message translates to:
  /// **'Sealed & witnessed via Wasiati'**
  String get wdocSealLine;

  /// No description provided for @wdocGuidance.
  ///
  /// In en, this message translates to:
  /// **'The fara’id shares herein are computed for guidance and are not a fatwa or legal advice; the estate is divided according to the sharia (fara’id) per the school selected by the testator.'**
  String get wdocGuidance;

  /// Label for the front-facing lens in the camera picker.
  ///
  /// In en, this message translates to:
  /// **'Front camera'**
  String get vrLensFront;

  /// Label for the rear-facing lens in the camera picker.
  ///
  /// In en, this message translates to:
  /// **'Back camera'**
  String get vrLensBack;

  /// Opens the list of available cameras on the video recorder.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get vrSwitchCamera;

  /// Heading over playback of a just-recorded video, before Retake/Use.
  ///
  /// In en, this message translates to:
  /// **'Your recording'**
  String get vrReviewTake;

  /// Shown when the recorded video cannot be decoded for preview.
  ///
  /// In en, this message translates to:
  /// **'That recording cannot be previewed here, but it did save — you can still use it.'**
  String get vrPlaybackFailed;

  /// Button that releases the camera device on the recorder screen.
  ///
  /// In en, this message translates to:
  /// **'Turn camera off'**
  String get vrCameraOff;

  /// Button that re-acquires the camera after it was turned off.
  ///
  /// In en, this message translates to:
  /// **'Turn camera on'**
  String get vrCameraOn;

  /// Shown over the dark viewfinder when the owner turned the camera off.
  ///
  /// In en, this message translates to:
  /// **'Camera off — your webcam light should be out.'**
  String get vrCameraOffNote;

  /// Opens every heir card on the heir registry step.
  ///
  /// In en, this message translates to:
  /// **'Expand all'**
  String get cwExpandAll;

  /// Closes every heir card on the heir registry step.
  ///
  /// In en, this message translates to:
  /// **'Collapse all'**
  String get cwCollapseAll;

  /// Shown on a collapsed heir card still missing a name, phone or email.
  ///
  /// In en, this message translates to:
  /// **'Needs details'**
  String get cwHeirNeedsDetails;

  /// No description provided for @portalAcceptTrusteeTitle.
  ///
  /// In en, this message translates to:
  /// **'Accept your trusteeship'**
  String get portalAcceptTrusteeTitle;

  /// No description provided for @portalAcceptTrusteeBody.
  ///
  /// In en, this message translates to:
  /// **'You were named trustee of this will, but you have not yet accepted the role. Accept it to open the estate and to act on behalf of the family.'**
  String get portalAcceptTrusteeBody;

  /// No description provided for @portalAcceptTrusteeBtn.
  ///
  /// In en, this message translates to:
  /// **'Accept the trusteeship'**
  String get portalAcceptTrusteeBtn;

  /// No description provided for @portalAssetRef.
  ///
  /// In en, this message translates to:
  /// **'REFERENCE'**
  String get portalAssetRef;

  /// No description provided for @portalInventoryNote.
  ///
  /// In en, this message translates to:
  /// **'Account references and contacts are shown in full so you can locate each asset. This list is erased with the rest of the estate at the end of the retrieval window — save what you need now.'**
  String get portalInventoryNote;

  /// No description provided for @apiOffline.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check your connection.'**
  String get apiOffline;

  /// No description provided for @dcGateWaitingHeirs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 heir has not confirmed} other{{count} heirs have not confirmed}}'**
  String dcGateWaitingHeirs(int count);

  /// No description provided for @dcGateWindow.
  ///
  /// In en, this message translates to:
  /// **'Safety window opens {when}'**
  String dcGateWindow(String when);

  /// No description provided for @dcGateNotSealed.
  ///
  /// In en, this message translates to:
  /// **'This will was never sealed'**
  String get dcGateNotSealed;

  /// No description provided for @dcGateNoTrustee.
  ///
  /// In en, this message translates to:
  /// **'No trustee has confirmed'**
  String get dcGateNoTrustee;

  /// No description provided for @dcGateOverride.
  ///
  /// In en, this message translates to:
  /// **'Heir confirmations overridden by a trustee'**
  String get dcGateOverride;

  /// No description provided for @dcGateReadyNote.
  ///
  /// In en, this message translates to:
  /// **'Everything release requires is satisfied.'**
  String get dcGateReadyNote;

  /// No description provided for @vaultPassphraseWrong.
  ///
  /// In en, this message translates to:
  /// **'That passphrase does not open this vault. Nothing was changed — check it and try again.'**
  String get vaultPassphraseWrong;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar': return AppLocalizationsAr();
    case 'en': return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
