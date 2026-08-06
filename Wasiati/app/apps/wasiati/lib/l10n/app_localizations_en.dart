// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Wasiati';

  @override
  String get navHome => 'Home';

  @override
  String get navWills => 'Wills';

  @override
  String get navVault => 'Vault';

  @override
  String get navBurial => 'Burial';

  @override
  String get navGuided => 'Guided';

  @override
  String get navLegacy => 'Legacy';

  @override
  String get navIdentity => 'Identity';

  @override
  String get navPlans => 'Plans';

  @override
  String get navAdmin => 'Admin';

  @override
  String get navUsers => 'Users';

  @override
  String get navClaims => 'Claims';

  @override
  String get navMore => 'More';

  @override
  String get navSettings => 'Settings';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonSeePlans => 'See plans';

  @override
  String get commonSignOut => 'Sign out';

  @override
  String get commonBack => 'Back';

  @override
  String get commonBackToWill => 'Back to will';

  @override
  String get wdBackToWills => 'My wills';

  @override
  String get brandTrustStrip => 'Sealed · Witnessed · Verified';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeDarkMode => 'Dark mode';

  @override
  String get settingsThemeMatchSystem => 'Match system theme';

  @override
  String get settingsRegionLanguage => 'Region & language';

  @override
  String get settingsRegion => 'Region';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'Match device';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageArabic => 'العربية';

  @override
  String get settingsRegionNote => 'Your region sets currency, tax rules and regional accounts. It\'s fixed to your account for data-residency reasons.';

  @override
  String get settingsSecurity => 'Security';

  @override
  String get settingsFaceApp => 'Face ID to open the app';

  @override
  String get settingsFaceVault => 'Face ID for the vault';

  @override
  String get settingsChangePassword => 'Change password';

  @override
  String get settingsChangePasswordSub => 'We\'ll email you a secure reset link.';

  @override
  String get settingsIdentity => 'Identity verification';

  @override
  String get settingsIdentitySub => 'Manage or complete ID verification.';

  @override
  String get settingsSignOutSub => 'Sign out on this device.';

  @override
  String get settingsLegal => 'Legal & support';

  @override
  String get settingsPrivacy => 'Privacy policy';

  @override
  String get settingsTerms => 'Terms of service';

  @override
  String get settingsContact => 'Contact support';

  @override
  String get settingsDeleteTitle => 'Delete my account';

  @override
  String get settingsDeleteBody => 'Deletion is handled by a person to protect against fraud on an account that holds a will. Email us and we\'ll verify and erase your data within 30 days.';

  @override
  String get settingsRequestDeletion => 'Request deletion';

  @override
  String settingsResetSent(String email) {
    return 'Password reset link sent to $email.';
  }

  @override
  String get settingsLinkError => 'Couldn\'t open the link.';

  @override
  String get settingsRoleAdmin => 'Admin';

  @override
  String get authWelcomeTagline => 'A dignified, Sharia-compliant will and legacy — sealed, witnessed, and verified.';

  @override
  String get authCreateYourWill => 'Create your will';

  @override
  String get authAlreadyHaveAccount => 'I already have an account';

  @override
  String get authRegionsLine => 'Saudi Arabia · Canada · United States';

  @override
  String get authWelcomeBack => 'Welcome to Wasiati';

  @override
  String get authLoginSubtitle => 'Region and currency are detected from your location — you’ll confirm them while creating your will.';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Password';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authNoAccountCreate => 'Don\'t have an account? Create one';

  @override
  String get authMoreWaysSoon => 'more ways to sign in — soon';

  @override
  String get authCreateAccount => 'Create your account';

  @override
  String get authRegisterSubtitle => 'Your will, encrypted vault, and legacy — in one place.';

  @override
  String get authRegion => 'Region';

  @override
  String get authPhoneOptional => 'Phone (optional, for SMS MFA)';

  @override
  String get authPhone => 'Phone number';

  @override
  String get authPhoneWhy => 'Used to sign you in and to reach your witnesses, trustee and family.';

  @override
  String get authPhoneRequired => 'Enter the phone number we can reach you on.';

  @override
  String get authVerifyPhoneTitle => 'Confirm your phone';

  @override
  String get authVerifyPhoneSubtitle => 'We sent a 6-digit code to the number you just gave us. This is the number we use to sign you in, and to reach your witnesses, trustee and family.';

  @override
  String get authVerifyPhoneCta => 'Confirm phone';

  @override
  String get authPhoneCodeResent => 'A new code is on its way.';

  @override
  String get addrCountry => 'Country';

  @override
  String get addrLine1 => 'Address';

  @override
  String get addrLine1Required => 'Enter your street address.';

  @override
  String get addrLine2Optional => 'Apartment, suite (optional)';

  @override
  String get addrCity => 'City';

  @override
  String get addrCityRequired => 'Enter your city.';

  @override
  String get addrState => 'State';

  @override
  String get addrProvince => 'Province';

  @override
  String get addrEmirate => 'Emirate';

  @override
  String get addrRegion => 'Region';

  @override
  String get addrAreaRequired => 'This is required for your country.';

  @override
  String get addrPostalCode => 'ZIP / postal code';

  @override
  String get addrPostalCodeOptional => 'Postal code (optional)';

  @override
  String get addrPostalRequired => 'Enter your postal code.';

  @override
  String get addrPostalInvalid => 'That postal code does not look right for this country.';

  @override
  String get addrWhy => 'Your address sets which law your will is written under, and appears in the final document.';

  @override
  String get authPasswordHelper => 'At least 10 characters';

  @override
  String get authCreateAccountButton => 'Create account';

  @override
  String get authHaveAccountSignIn => 'Already have an account? Sign in';

  @override
  String get authInvalidEmail => 'Enter a valid email';

  @override
  String get authEnterPassword => 'Enter your password';

  @override
  String get authUseTenChars => 'Use at least 10 characters';

  @override
  String get authGenericError => 'Something went wrong. Please try again.';

  @override
  String get regionUnitedStates => 'United States';

  @override
  String get regionCanada => 'Canada';

  @override
  String get regionSaudiArabia => 'Saudi Arabia';

  @override
  String get willOpeningInsert => 'Insert an Islamic opening';

  @override
  String get willOpeningSubtitle => 'Begin with the bismillah and the shahada, grounded in Qur\'an and Sunnah. Optional — keep it, edit it, or clear it.';

  @override
  String get willOpeningFull => 'Full';

  @override
  String get willOpeningShort => 'Short';

  @override
  String get willOpeningInserted => 'Opening inserted — edit or clear it as you wish.';

  @override
  String get mfaTitle => 'Enter the 6-digit code';

  @override
  String mfaResendWait(int n) {
    return 'Resend in ${n}s';
  }

  @override
  String get mfaResendReady => 'Didn’t get it?';

  @override
  String get mfaResend => 'Resend code';

  @override
  String get mfaSubtitleSms => 'We sent an SMS with a 6-digit code to your phone.';

  @override
  String get mfaSubtitleWhatsapp => 'We sent a 6-digit code to your WhatsApp.';

  @override
  String get mfaSubtitleTotp => 'Open your authenticator app and enter the 6-digit code it shows.';

  @override
  String get secRcTitle => 'Backup codes';

  @override
  String get secRcNone => 'Not set up — you could be locked out if you lose your phone';

  @override
  String secRcRemaining(int count, int total) {
    return '$count of $total left';
  }

  @override
  String secRcLow(int count) {
    return 'Only $count left — generate a new set';
  }

  @override
  String get secRcGenerate => 'Generate backup codes';

  @override
  String get secRcRegenerate => 'Generate a new set';

  @override
  String get secRcSaveNow => 'Save these now. They are shown once and cannot be recovered — each one signs you in a single time if you lose your phone.';

  @override
  String get secRcReplaces => 'Generating a new set immediately cancels your current codes.';

  @override
  String get secRcCopy => 'Copy all';

  @override
  String get secRcCopied => 'Backup codes copied.';

  @override
  String get secRcDone => 'I have saved them';

  @override
  String get secTotpTitle => 'Authenticator app';

  @override
  String get secTotpBlurb => 'Sign in with a code from an app like Google Authenticator or 1Password. Free, works without signal, and safer than a text message.';

  @override
  String get secTotpOn => 'On';

  @override
  String get secTotpOff => 'Not set up';

  @override
  String get secTotpSetUp => 'Set up';

  @override
  String get secTotpTurnOff => 'Turn off';

  @override
  String get secTotpScan => 'Scan this in your authenticator app, or paste the key below, then enter the 6-digit code it shows.';

  @override
  String get secTotpKey => 'Setup key';

  @override
  String get secTotpConfirm => 'Confirm';

  @override
  String get secTotpEnabled => 'Authenticator app is on. You will no longer be texted a code.';

  @override
  String get secTotpDisabled => 'Authenticator app turned off. Codes will be sent to you again.';

  @override
  String get secTotpCodeLabel => '6-digit code';

  @override
  String get mfaSubtitleEmail => 'We emailed a 6-digit code to your inbox.';

  @override
  String get mfaVerify => 'Verify';

  @override
  String get forgotTitle => 'Reset your password';

  @override
  String get forgotSubtitle => 'Enter your email and we\'ll send a 6-digit code.';

  @override
  String forgotSentBody(String email) {
    return 'If an account exists for $email, a reset link is on its way. The link expires in 1 hour.';
  }

  @override
  String get forgotSendCode => 'Send code';

  @override
  String forgotCodeSentBody(String email) {
    return 'If an account exists for $email, a 6-digit code is on its way — by text message when a phone is on file, otherwise by email.';
  }

  @override
  String get forgotBackToSignIn => 'Back to sign in';

  @override
  String get forgotSendResetLink => 'Send reset link';

  @override
  String get resetSuccess => 'Password reset. Please sign in.';

  @override
  String get resetInvalidTitle => 'Invalid reset link';

  @override
  String get resetInvalidSubtitle => 'This link is missing or malformed. Request a new one.';

  @override
  String get resetRequestNew => 'Request a new link';

  @override
  String get resetTitle => 'Choose a new password';

  @override
  String get resetNewPasswordLabel => 'New password';

  @override
  String get resetHelper => 'At least 10 characters';

  @override
  String get resetValidator => 'Use at least 10 characters';

  @override
  String get resetSubmit => 'Reset password';

  @override
  String get verifyEmailSent => 'Verification email sent.';

  @override
  String get verifyEmailVerifyingTitle => 'Verifying your email';

  @override
  String get verifyEmailInvalid => 'This verification link is invalid or has expired.';

  @override
  String get verifyEmailResend => 'Resend verification email';

  @override
  String get verifyEmailVerified => 'Your email is verified.';

  @override
  String get verifyEmailContinue => 'Continue';

  @override
  String get verifyEmailSignIn => 'Sign in';

  @override
  String get verifyEmailTitle => 'Verify your email';

  @override
  String get verifyEmailSubtitle => 'Check your inbox for a verification link.';

  @override
  String dashGreeting(String name) {
    return 'Assalamu alaikum, $name';
  }

  @override
  String get dashStandardPlan => 'Standard plan';

  @override
  String get dashCreateWill => 'Create will';

  @override
  String get dashWillsLoadError => 'We couldn\'t load your wills.';

  @override
  String get dashPrimaryWill => 'Your primary will';

  @override
  String get dashPrimaryWillSealed => 'Your will — sealed';

  @override
  String dashHeirCount(int count) {
    return '$count heirs';
  }

  @override
  String dashBequest(String pct) {
    return '$pct% in bequests';
  }

  @override
  String get dashSealed => 'Sealed';

  @override
  String get dashDraft => 'Draft';

  @override
  String get dashViewWill => 'View will';

  @override
  String get dashSharesBreakdown => 'Shares breakdown';

  @override
  String get dashBeginWill => 'Begin your will';

  @override
  String get dashBeginBody => 'A few minutes now spares your family months later. We compute the Sharia shares as you go.';

  @override
  String get dashCreateYourWill => 'Create your will';

  @override
  String get dashPlanLoadError => 'Couldn\'t load your plan.';

  @override
  String get dashYourPlan => 'Your plan';

  @override
  String get dashCompedAccess => 'Comped access';

  @override
  String get dashFeatureUnlimitedEdits => 'Unlimited will edits';

  @override
  String get dashFeatureEncryptedVault => 'Encrypted vault';

  @override
  String get dashFeatureVideoLegacy => 'Video legacy messages — Premium';

  @override
  String get dashVerified => 'Identity verified';

  @override
  String get dashUpgradePremium => 'Upgrade to Premium';

  @override
  String get dashHeirs => 'Heirs';

  @override
  String get dashHeirsCaption => 'named in your will';

  @override
  String get dashWitnesses => 'Witnesses';

  @override
  String get dashWitnessesCaption => 'attesting your will';

  @override
  String get dashTrustees => 'Trustees';

  @override
  String get dashTrusteesCaption => 'who carry it out';

  @override
  String get dashIdPending => 'Pending review';

  @override
  String get dashIdUnverified => 'Identity not verified';

  @override
  String get dashChecklistTitle => 'Your legacy, in order';

  @override
  String dashChecklistCount(int done, int total) {
    return '$done / $total';
  }

  @override
  String get dashCkIdentity => 'Identity verified';

  @override
  String get dashCkHeirs => 'Heirs added';

  @override
  String get dashCkSealed => 'Will sealed';

  @override
  String get dashCkVideo => 'Record a video message';

  @override
  String get dashWillsSummaryTitle => 'Your wills';

  @override
  String dashSealedCountLine(int count) {
    return '$count sealed · witnessed';
  }

  @override
  String get dashNoDraftLine => 'nothing in draft';

  @override
  String get dashDraftLbl => 'DRAFT';

  @override
  String dashDraftStep(int step) {
    return 'Step $step of 6';
  }

  @override
  String get dashContinueDraft => 'Continue';

  @override
  String get dashOpen => 'Open';

  @override
  String get dashVault => 'Vault';

  @override
  String get dashSecretsStored => 'secrets stored';

  @override
  String get dashEncryptedLocked => 'Client-side encrypted · locked';

  @override
  String get dashHeirContacts => 'Heir contacts';

  @override
  String get dashContactsMissing => 'missing';

  @override
  String get dashContactsComplete => 'complete';

  @override
  String get dashContactsMeta => 'Name, mobile & email per heir';

  @override
  String get dashConfirmed => 'confirmed';

  @override
  String get dashTrustee => 'Trustee';

  @override
  String get dashPendingCode => 'pending code';

  @override
  String get dashResendSms => 'Resend SMS code';

  @override
  String get dashFeatureVideoLegacyUnlocked => 'Video legacy messages';

  @override
  String get dashRefReminder => 'Share Wasiati, earn 2.5% of each friend’s first year — they get 10% off.';

  @override
  String get burialTitle => 'Burial planning';

  @override
  String get burialSubtitle => 'See what a dignified Islamic burial costs in your city today, and what that would come to in small, equal contributions — no interest, no profit.';

  @override
  String get burialCity => 'City';

  @override
  String get burialCityHint => 'Toronto, ON';

  @override
  String get burialCostToday => 'Cost today';

  @override
  String get burialMaxPeriod => '10 years is the longest plan.';

  @override
  String get burialSavePlan => 'Save this estimate';

  @override
  String get burialCovers => 'Covers ghusl, kafan, janazah services, plot and burial. When prepayment opens, your grave would be reserved with a local mosque at today\'s price and your contributions held for you — we take no interest or profit. Ultimate plan, Canada & US.';

  @override
  String burialYearsShort(int years) {
    return '$years yrs';
  }

  @override
  String get burialPlanHeader => 'YOUR BURIAL ESTIMATE';

  @override
  String burialPlanHeaderCity(String city) {
    return 'YOUR BURIAL ESTIMATE — $city';
  }

  @override
  String get burialAddedToSub => 'Would be per month';

  @override
  String burialPerMonth(String money) {
    return '$money /mo';
  }

  @override
  String get burialFundedBy => 'Fully funded by';

  @override
  String get burialWantRealNumber => 'Want a real number?';

  @override
  String get burialQuoteDesc => 'We\'ll request a quote from Islamic funeral providers near you.';

  @override
  String get burialRequestQuote => 'Request a quote';

  @override
  String get burialUltimatePlan => 'Ultimate plan (US & Canada)';

  @override
  String get burialUltimateDesc => 'Burial planning is part of the Ultimate plan.';

  @override
  String burialEstimateSummary(String cost, int months) {
    return '$cost · $months equal contributions · no interest, no profit';
  }

  @override
  String burialProviderQuote(String amount) {
    return 'Provider quote: $amount';
  }

  @override
  String burialProviderQuoteNotes(String amount, String notes) {
    return 'Provider quote: $amount · $notes';
  }

  @override
  String get burialQuoteRequested => 'Quote requested — an admin is sourcing a real quote.';

  @override
  String get burialRequestRealQuote => 'Request a real quote';

  @override
  String get burialSavedPlans => 'Your saved plans';

  @override
  String get burialPlanSaved => 'Estimate saved.';

  @override
  String get burialEnterCityCost => 'Enter a city and today\'s cost.';

  @override
  String get adminCommerceEyebrow => 'ADMIN — COMMERCE';

  @override
  String get adminCommerceTitle => 'Catalog, promotions & offers';

  @override
  String get adminCommerceTabPlans => 'Plans';

  @override
  String get adminCommerceTabPromotions => 'Promotions';

  @override
  String get adminCommerceTabOffers => 'Offers';

  @override
  String get adminConsoleTitle => 'Console';

  @override
  String get adminConsolePill => 'ADMIN';

  @override
  String adminPlanPriceLabel(String currency) {
    return 'Price ($currency)';
  }

  @override
  String get adminPlanPriceUpdated => 'Price updated — live everywhere.';

  @override
  String get adminPlanEditPrice => 'Edit price';

  @override
  String get adminPromoNewTitle => 'New promotion';

  @override
  String get adminPromoCodeLabel => 'Code (e.g. LAUNCH25)';

  @override
  String get adminPromoTypeLabel => 'Type';

  @override
  String get adminPromoTypePercent => 'Percent off';

  @override
  String get adminPromoTypeAmount => 'Amount off (USD)';

  @override
  String get adminPromoValuePercentLabel => 'Percent (1-100)';

  @override
  String get adminPromoValueAmountLabel => 'Amount (cents)';

  @override
  String get adminPromoCreate => 'Create';

  @override
  String get adminPromoCreated => 'Promotion created.';

  @override
  String get adminPromoNewButton => 'New promo';

  @override
  String get adminPromoEmpty => 'No promotions yet.';

  @override
  String adminPromoUsed(int count) {
    return 'used $count×';
  }

  @override
  String get adminPromoLimitsSection => 'Limits';

  @override
  String get adminPromoMaxRedemptionsLabel => 'Max redemptions';

  @override
  String get adminPromoMaxRedemptionsHelper => 'Leave empty for unlimited';

  @override
  String get adminPromoStartsAtLabel => 'Starts';

  @override
  String get adminPromoEndsAtLabel => 'Ends';

  @override
  String get adminPromoDateAny => 'Any time';

  @override
  String get adminPromoDateClear => 'Clear';

  @override
  String get adminPromoErrorEndBeforeStart => 'The end date must be after the start date.';

  @override
  String get adminPromoErrorCodeRequired => 'Enter a code.';

  @override
  String adminPromoUsedOf(int used, int max) {
    return '$used of $max used';
  }

  @override
  String adminPromoWindowFrom(String date) {
    return 'from $date';
  }

  @override
  String adminPromoWindowUntil(String date) {
    return 'until $date';
  }

  @override
  String get adminPromoStatusLive => 'Live';

  @override
  String get adminPromoStatusScheduled => 'Scheduled';

  @override
  String get adminPromoStatusExpired => 'Expired';

  @override
  String get adminPromoStatusExhausted => 'Limit reached';

  @override
  String get adminPromoStatusInactive => 'Inactive';

  @override
  String get adminPromoEditTitle => 'Edit promotion';

  @override
  String get adminPromoEditTooltip => 'Edit';

  @override
  String get adminPromoUpdated => 'Promotion updated.';

  @override
  String get adminPromoArchive => 'Archive';

  @override
  String get adminPromoArchived => 'Promotion archived — it can be reinstated at any time.';

  @override
  String get adminPromoReinstate => 'Reinstate';

  @override
  String get adminPromoReinstated => 'Promotion reinstated.';

  @override
  String get adminPromoFirstTimeOnlyLabel => 'First subscription only';

  @override
  String get adminPromoFirstTimeOnlyHelper => 'Customers who have bought before are refused this code.';

  @override
  String get adminOfferEmpty => 'No offers yet.';

  @override
  String get adminOfferLive => 'Live';

  @override
  String get adminOfferOff => 'Off';

  @override
  String get adminOfferEditTitle => 'Edit offer';

  @override
  String get adminOfferEditTooltip => 'Edit';

  @override
  String get adminOfferTitleLabel => 'Title';

  @override
  String get adminOfferSubtitleLabel => 'Subtitle';

  @override
  String get adminOfferBadgeLabel => 'Badge';

  @override
  String get adminOfferCtaLabel => 'Button label';

  @override
  String get adminOfferErrorTitleRequired => 'A title is required.';

  @override
  String get adminOfferSaved => 'Offer updated.';

  @override
  String get adminOfferActivated => 'Offer is live.';

  @override
  String get adminOfferDeactivated => 'Offer switched off.';

  @override
  String get adminOfferDeleteTitle => 'Delete this offer?';

  @override
  String get adminOfferDeleteBody => 'It disappears from the storefront immediately. Unlike a promotion, a deleted offer cannot be reinstated.';

  @override
  String get adminOfferDeleted => 'Offer deleted.';

  @override
  String get relHusband => 'Husband';

  @override
  String get relWife => 'Wife';

  @override
  String get relSon => 'Son';

  @override
  String get relDaughter => 'Daughter';

  @override
  String get relFather => 'Father';

  @override
  String get relMother => 'Mother';

  @override
  String get relGrandfather => 'Grandfather';

  @override
  String get relGrandmother => 'Grandmother';

  @override
  String get relBrother => 'Brother (full)';

  @override
  String get relSister => 'Sister (full)';

  @override
  String get relMaternalSibling => 'Sibling (maternal half)';

  @override
  String get relSonSon => 'Son\'s son (grandson)';

  @override
  String get relSonDaughter => 'Son\'s daughter (granddaughter)';

  @override
  String get relPaternalGrandmother => 'Grandmother (paternal)';

  @override
  String get relMaternalGrandmother => 'Grandmother (maternal)';

  @override
  String get relConsanguineBrother => 'Brother (paternal half)';

  @override
  String get relConsanguineSister => 'Sister (paternal half)';

  @override
  String get relFullNephew => 'Brother\'s son (full)';

  @override
  String get relConsanguineNephew => 'Brother\'s son (paternal half)';

  @override
  String get relFullUncle => 'Paternal uncle (full)';

  @override
  String get relConsanguineUncle => 'Paternal uncle (paternal half)';

  @override
  String get relFullCousin => 'Paternal uncle\'s son (full)';

  @override
  String get relConsanguineCousin => 'Paternal uncle\'s son (paternal half)';

  @override
  String get cwPageTitle => 'Create your will';

  @override
  String get cwStep1 => 'Step 1 of 4 — Family & heirs';

  @override
  String get cwFamilyHeirs => 'Family & heirs';

  @override
  String get cwWhoHeirs => 'Who are your heirs?';

  @override
  String get cwHeirsSubtitle => 'Add family members; shares are computed automatically to the fara\'id.';

  @override
  String get cwSavedAuto => 'Draft saved — you can leave and continue later';

  @override
  String get cwFillAi => 'Ask Ameen to fill it';

  @override
  String get cwBack => '‹ Back';

  @override
  String get cwContinueBequests => 'Continue to bequests ›';

  @override
  String get cwStep2 => 'STEP 2 OF 4 — BEQUEST';

  @override
  String get cwBequestTitle => 'The free third';

  @override
  String get cwBequestSubtitle => 'Up to one third of your estate may go to charity or to someone who does not inherit — a stepchild, a friend. Your heirs\' fixed shares are never touched.';

  @override
  String get cwBequestWhoLabel => 'Who receives it';

  @override
  String get cwBequestWhoHint => 'A charity, a stepchild, a friend…';

  @override
  String get cwBequestAmount => 'Bequest';

  @override
  String get cwOfEstate => 'of the estate';

  @override
  String get cwOfFreeThird => 'of the free third';

  @override
  String get cwWithinCap => 'Within the one-third cap';

  @override
  String get cwBequestHelp => 'Drag to set how much to leave. It can never exceed one third (⅓) — the fara\'id shares always come first.';

  @override
  String get cwCreateMyWill => 'Create my will ›';

  @override
  String get cwBequestNameNeeded => 'Name who receives the bequest first.';

  @override
  String get cwContinueWords => 'Continue to words ›';

  @override
  String get cwStep3 => 'STEP 3 OF 4 — WORDS';

  @override
  String get cwWordsTitle => 'Words for my family';

  @override
  String get cwWordsSubtitle => 'A personal message inside your will — released with it, up to 5,000 characters.';

  @override
  String get cwWordsHint => 'In the name of Allah, the Most Gracious, the Most Merciful. This is what I enjoin upon my family: I testify that there is no god but Allah…    ↵ Press Enter to start from the classic wasiyya — or write your own';

  @override
  String get cwWordsDefault => 'In the name of Allah, the Most Gracious, the Most Merciful.\n\nThis is what I enjoin upon my family: I testify that there is no god but Allah, alone without partner, and that Muhammad صلى الله عليه وسلم is His servant and Messenger; that Paradise is true, the Fire is true, and the Hour is coming without doubt, and Allah will resurrect those in the graves.\n\nI enjoin you to fear Allah, to set right what is between you, and to obey Allah and His Messenger if you are believers. Hold to prayer, be dutiful to one another, and forgive me my shortcomings. Settle my debts, and remember me in your duʿa\'.';

  @override
  String get cwRelation => 'Relation';

  @override
  String get cwName => 'Name';

  @override
  String get cwLivePreview => 'LIVE FARA’ID PREVIEW';

  @override
  String get cwLivePreviewShort => 'FARA\'ID';

  @override
  String cwHeirCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count heirs',
      one: '1 heir',
    );
    return '$_temp0';
  }

  @override
  String get cwUpdatesAsType => 'updates as you type';

  @override
  String get cwPreviewFootnote => 'Shares follow the fara\'id for the heirs you\'ve entered. The server recomputes and enforces the final split when you continue.';

  @override
  String get cwAddHeirPrompt => 'Add an heir to see the live breakdown.';

  @override
  String get cwSexLabel => 'I am';

  @override
  String get cwMale => 'Male';

  @override
  String get cwFemale => 'Female';

  @override
  String get cwWivesLabel => 'Spouses';

  @override
  String get cwSpousesHelp => 'Up to 4 wives — the spousal share is divided equally among them.';

  @override
  String get cwHusbandLabel => 'Husband';

  @override
  String get cwChildrenLabel => 'Children';

  @override
  String get cwParentsLabel => 'Parents';

  @override
  String get cwFamilyFootnote => 'Only living heirs at the time of death inherit. You\'ll confirm your region while creating your will.';

  @override
  String get cwAddExtended => 'Add extended family — grandparents, siblings, uncles, cousins';

  @override
  String get cwExtendedFamily => 'Extended family';

  @override
  String get cwSettleFootnote => 'Debts you owe and any bequest (≤ ⅓) are settled before these shares.';

  @override
  String get cwBeforeShares => 'BEFORE SHARES ARE DIVIDED';

  @override
  String get cwStep1Funeral => 'Funeral expenses';

  @override
  String get cwStep2Debts => 'Debts you owe (owed money) — settled in full first';

  @override
  String get cwStep3Bequest => 'Bequest — up to one third of what remains';

  @override
  String get cwSharesApplyRest => 'The shares below apply to the rest of the estate.';

  @override
  String get cwMadhhabQuestion => 'Which school of jurisprudence (fiqh) do you follow?';

  @override
  String get cwMadhhabJumhur => 'Jumhūr — the majority position as applied today, followed by Mālikī, Shāfiʿī and Ḥanbalī communities';

  @override
  String get cwMadhhabHanafi => 'Ḥanafī — differs where a grandfather inherits alongside siblings';

  @override
  String get cwMadhhabMaliki => 'Maliki';

  @override
  String get cwMadhhabShafii => 'Shafi\'i';

  @override
  String get cwMadhhabHanbali => 'Hanbali';

  @override
  String get cwMadhhabNote => 'The schools differ in one place for these heirs: whether a grandfather shares with siblings (majority) or blocks them (Ḥanafī). On returning a surplus to the heirs (radd), contemporary practice across the schools agrees.';

  @override
  String cwComputedPer(String school) {
    return 'Computed per: $school';
  }

  @override
  String get cwDisclaimer => 'I understand this document expresses my wishes under Islamic inheritance principles and that Wasiati does not provide legal advice. Requirements vary by jurisdiction; I may need witnesses or notarization for enforceability.';

  @override
  String cwStepOf(String step, String name) {
    return 'Step $step of 6 — $name';
  }

  @override
  String get cwStepName1 => 'Family & heirs';

  @override
  String get cwStepName2 => 'Heir registry';

  @override
  String get cwStepName3 => 'Witnesses, trustee & guardian';

  @override
  String get cwStepName4 => 'Your estate & bequest';

  @override
  String get cwStepName5 => 'Wishes & words';

  @override
  String get cwStepName6 => 'Review & confirm';

  @override
  String get cwNavBack => 'Back';

  @override
  String get cwNavContinue => 'Continue';

  @override
  String get cwEstateTitle => 'Your estate today';

  @override
  String get cwEstateEdit => 'Edit assets & loans';

  @override
  String cwShowAllRows(String n) {
    return 'Show all $n assets & loans';
  }

  @override
  String cwFxNote(String currency) {
    return 'Foreign amounts converted to $currency — your local currency, from your region — at today\'s rate.';
  }

  @override
  String get cwEstateAssets => 'ASSETS';

  @override
  String get cwEstateLoans => 'DEBTS';

  @override
  String get cwEstateNet => 'NET ESTATE';

  @override
  String get cwEstateNote => 'From your inventory. Funeral costs and debts are settled first, then your bequest (max ⅓), then fara\'id shares. Vault secrets stay out of the will — they release separately, encrypted.';

  @override
  String get cwEstateEmpty => 'Nothing here yet — list what you own and owe so your family never has to search.';

  @override
  String get cwBequestCardTitle => 'Bequest — the free third';

  @override
  String get cwBequestCardSub => 'For charity, sadaqah jariyah, or people who don\'t inherit (a step-child, a friend). Capped at one third of the estate; heirs\' shares are never touched.';

  @override
  String get cwBequestPctLabel => 'Bequest — % of the free third';

  @override
  String get cwBequestHelpLead => 'Up to one third of the estate may be bequeathed outside the fara\'id. Your current bequest equals';

  @override
  String get cwOfEstateDot => 'of the estate.';

  @override
  String get cwWishesCardTitle => 'Funeral & burial wishes';

  @override
  String get cwWish1 => 'Ghusl and shrouding per the Sunnah';

  @override
  String get cwWish2 => 'A simple burial — no extravagance, no delay';

  @override
  String get cwWish3 => 'Bury me in the nearest Muslim cemetery';

  @override
  String get cwWish4 => 'Hold an ʿazāʾ (condolence gathering) — three days, no more';

  @override
  String get cwWish4No => 'No ʿazāʾ gathering — duʿāʾ suffices';

  @override
  String get cwWishesNote => 'Recorded in your will so your family isn\'t guessing at the hardest moment.';

  @override
  String get cwSealBtn => 'Create & seal';

  @override
  String get cwMotherLbl => 'Mother living';

  @override
  String get cwFatherLbl => 'Father living';

  @override
  String get cwGmotherLbl => 'Grandmother living';

  @override
  String get cwGmotherMaternalLbl => 'Grandmother — mother’s mother';

  @override
  String get cwGmotherPaternalLbl => 'Grandmother — father’s mother';

  @override
  String get cwGfatherLbl => 'Grandfather (paternal) living';

  @override
  String get cwExtendedHead => 'EXTENDED FAMILY — COUNTED ONLY WHEN THEY QUALIFY';

  @override
  String get cwBrothersLbl => 'Brothers (full)';

  @override
  String get cwSistersLbl => 'Sisters (full)';

  @override
  String get cwUnclesLbl => 'Paternal uncles';

  @override
  String get cwCousinsLbl => 'Cousins (uncle\'s sons)';

  @override
  String get cwDhawuNote => 'If you have a son, your siblings, uncles and cousins inherit nothing — he blocks them entirely; with only daughters, an uncle may still take what remains after the fixed shares. Aunts, maternal uncles and their children are dhawu al-arham: Hanafis let them inherit when no sharer or residuary exists; Maliki and Shafi\'i schools classically do not. Step-parents, step-children and adopted children do not inherit by sharia — provide for them through your bequest (up to ⅓) in the next step.';

  @override
  String get cwPreviewNote => 'Shares update as you edit. Each share carries its basis — shown in the review step.';

  @override
  String get cwHeirRegTitle => 'Heir registry';

  @override
  String get cwHeirRegSub => 'Full name, mobile number and email for every heir — required so the will can be released to each of them at claim time.';

  @override
  String get cwFullNameLbl => 'FULL NAME';

  @override
  String get cwFullNamePh => 'Full legal name';

  @override
  String get cwPhoneLbl => 'PHONE';

  @override
  String get cwEmailLbl => 'EMAIL';

  @override
  String get cwPhonePh => '+966 55 123 4567';

  @override
  String get cwEmailPh => 'care@bank.com';

  @override
  String get cwMinorLbl => 'Under 18';

  @override
  String get cwGuardianNote => 'Under 18 — the share is held in trust for them until they come of age, under the guardian set in the will flow (default: the surviving parent). Contact details route to the guardian.';

  @override
  String get cwHeirRegSeeded => 'Pre-loaded from your family answers — these are the heirs who inherit under the fara\'id. Anyone blocked from inheriting is left out. Edit, add or remove rows as you need.';

  @override
  String get cwAddHeirBtn => '+ Add heir';

  @override
  String get cwHeirRegMissing => 'Every heir needs a full name, mobile number and email before the will can be sealed.';

  @override
  String get cwHeirRegDone => 'All heirs have complete contact details';

  @override
  String get cwRelOther => 'Other';

  @override
  String get cwWitTrustTitle => 'Witnesses & trustee';

  @override
  String get cwWitTrustSub => 'Two witnesses and a trustee confirm by SMS before the will can be sealed. You can review everything without them.';

  @override
  String get cwRoleWitness => 'Witness';

  @override
  String get cwRoleTrustee => 'Trustee';

  @override
  String get cwPendingLbl => 'PENDING';

  @override
  String get cwConfirmedLbl => 'CONFIRMED';

  @override
  String get cwWitGateNote => 'Sealing unlocks once both witnesses and the trustee confirm — reviewing stays open meanwhile.';

  @override
  String get cwAddWitness => '+ Add witness';

  @override
  String cwWitnessCountReq(String added, String required) {
    return '$added of $required required';
  }

  @override
  String cwWitnessMinNote(String required) {
    return 'Add at least $required witnesses to continue — a will cannot be signed or sealed with fewer.';
  }

  @override
  String get cwAddTrustee => '+ Add trustee';

  @override
  String get cwAdd => 'Add';

  @override
  String get cwCancel => 'Cancel';

  @override
  String get cwGuardTitle => 'Guardianship of minor children';

  @override
  String get cwGuardSub => 'Who cares for your children under 18. By default the surviving parent; or follow the Islamic order of guardianship; or name someone you trust.';

  @override
  String get cwGParentLbl => 'Surviving parent (default)';

  @override
  String get cwGIslamicLbl => 'Islamic order of guardianship';

  @override
  String get cwGNamedLbl => 'Name a guardian';

  @override
  String get cwGParentNote => 'The other parent is recorded as guardian of the person and of each minor\'s share until they come of age.';

  @override
  String get cwGIslamicNote => 'This option names no one. It directs that your children’s care, and guardianship of their share, be settled under the sharia rules and the competent court applying at the time — the schools differ, and the two need not fall to the same person. To choose the person yourself, which every school allows, use “Name a guardian”.';

  @override
  String get cwReviewTitle => 'Review & confirm';

  @override
  String get cwReviewPeople => 'Witnesses, trustee & guardian';

  @override
  String cwReviewGuardianLine(String who) {
    return 'Guardian of minors: $who';
  }

  @override
  String cwWordsCount(int count) {
    return '$count / 5000';
  }

  @override
  String get cwSealNeedsDisclaimer => 'Tick the confirmation above to seal.';

  @override
  String get cwEstateSummaryTitle => 'Estate summary';

  @override
  String get cwUpgrade => 'Upgrade';

  @override
  String get draftWillTitle => 'My will — in progress';

  @override
  String get draftLbl => 'DRAFT';

  @override
  String get draftContinue => 'Continue';

  @override
  String get draftAutosaved => 'autosaved';

  @override
  String get rsVideoTitle => 'A VIDEO FOR YOUR FAMILY';

  @override
  String get rsVideoGateNote => 'Video messages are a Premium feature. Upgrade to record encrypted video for your loved ones.';

  @override
  String get rsVideoRecord => 'Record video';

  @override
  String get rsVideoUpload => 'Upload video';

  @override
  String get rsVideoSkip => 'Skip for now';

  @override
  String get rsVideoNote => 'Record now or upload a file — encrypted like the vault, released with the will. Heirs see only that a message exists.';

  @override
  String get rsVideoSavedNote => 'Encrypted · stored in your vault · plays after release';

  @override
  String get rsVideoDelete => 'Delete';

  @override
  String get rsVideoDeferredNote => 'Deferred — your will is complete without it; you can add a video any time.';

  @override
  String get rsVideoRecordNow => 'Record now';

  @override
  String get rsVideoSavedToast => 'Video encrypted and saved to your vault';

  @override
  String get rsVideoDeferredToast => 'Skipped — you can add a video from your will any time';

  @override
  String get rsVideoMsgLabel => 'Video message';

  @override
  String get rsVideoBadFile => 'Choose an mp4, webm or mov video file.';

  @override
  String get wlTitle => 'Your wills';

  @override
  String get wlSubtitle => 'A sealed will can be reopened for editing on Standard and above.';

  @override
  String get wlCreateWill => 'Create will';

  @override
  String get wlCapNote => 'You can keep up to 3 drafts — delete one to start another.';

  @override
  String get wlNoWillsTitle => 'No wills yet';

  @override
  String get wlNoWillsSubtitle => 'Your will takes about ten minutes. We guide you through every step.';

  @override
  String get wlCreateYourWill => 'Create your will';

  @override
  String get wlPrimaryWill => 'My primary will';

  @override
  String get wlAdditionalWill => 'Additional will';

  @override
  String get wlSealed => 'Sealed';

  @override
  String get wlDraftNotSealed => 'Draft — not yet sealed';

  @override
  String get wlMetaSealed => 'sealed';

  @override
  String get wlMetaDraft => 'draft';

  @override
  String wlMetaBequest(String pct) {
    return 'bequest $pct% of the free third';
  }

  @override
  String wlTitleSealed(String title) {
    return '$title — sealed';
  }

  @override
  String wlMetaWitnesses(int confirmed, int required) {
    return '$confirmed of $required witnesses confirmed';
  }

  @override
  String wlMetaUpdated(String date) {
    return 'updated $date';
  }

  @override
  String wlSealedSupersede(String date) {
    return 'sealed $date — a newer sealed will supersedes it automatically';
  }

  @override
  String get wlSecondWillTitle => 'A second will';

  @override
  String get wlSecondWillBody => 'For assets in another country or a different madhhab preference.';

  @override
  String get wlStart => 'Start';

  @override
  String get wlOpen => 'Open';

  @override
  String get wlSharesBreakdown => 'Shares breakdown';

  @override
  String get wlContinue => 'Continue';

  @override
  String get wlCreateAnotherPrompt => 'Need a separate will for another jurisdiction? ';

  @override
  String get wlCreateAnother => 'Create another will';

  @override
  String get wlLoadErrorTitle => 'Could not load your wills.';

  @override
  String get wlTryAgain => 'Try again';

  @override
  String get wlDeleteWill => 'Delete will';

  @override
  String get wlDocsExtraTitle => 'Directives — beyond the will';

  @override
  String get wlPoaTitle => 'Financial power of attorney';

  @override
  String get wlPoaSub => 'Authorizes a trusted agent to manage your finances if you become unable to — separate from your will, effective in life.';

  @override
  String get wlHcdTitle => 'Healthcare directive';

  @override
  String get wlHcdSub => 'Your treatment wishes and a healthcare agent, recorded with Islamic guidance in mind — separate from your will, effective in life.';

  @override
  String get wlDocSigned => 'Signed';

  @override
  String get wlDocNotStarted => 'Not started';

  @override
  String get wlDocPrepare => 'Prepare & sign';

  @override
  String get wlDocEdit => 'Edit';

  @override
  String get wlDocSaveSign => 'Save & sign';

  @override
  String get wlDocAgentNameLbl => 'AGENT FULL NAME';

  @override
  String get wlDocWishesLbl => 'TREATMENT WISHES';

  @override
  String get wlDocWishesPh => 'e.g. no prolonged life support; consult my healthcare agent and a scholar';

  @override
  String wlDocAgentLine(Object name) {
    return 'Agent: $name · witnessed digitally';
  }

  @override
  String get wlDocToastSigned => 'Signed & witnessed digitally · stored with your documents';

  @override
  String get wlDocGatedNudge => 'Included with Premium and Ultimate.';

  @override
  String get wlDirectivesLink => 'separate documents, effective during your life. Manage them from the Wills page.';

  @override
  String get wlManage => 'Manage';

  @override
  String get wlDeleteWillTitle => 'Delete this will?';

  @override
  String get wlDeleteWillBody => 'This permanently deletes the sealed will, its shares and bequests, and the assets recorded on it. Your vault is not touched. We need to confirm it is really you.';

  @override
  String get wlDeleteDraftTitle => 'Delete this draft?';

  @override
  String get wlDeleteDraftBody => 'This permanently deletes the draft and everything recorded on it — heirs, shares, bequests and assets. It has not been signed or witnessed, so nothing else is affected. Your vault is not touched. We need to confirm it is really you.';

  @override
  String get wlDeleteOtpLabel => 'Enter the SMS code we sent';

  @override
  String get wlDeleteDone => 'Will deleted.';

  @override
  String get sealTitle => 'Your will is sealed';

  @override
  String get sealBody => 'Witnessed, computed to the fara\'id, encrypted and safe. May it not be needed for a very long time.';

  @override
  String get sealWry => '“Thank God they\'ll only be reading this when I\'m gone.”';

  @override
  String get sealViewWill => 'View will';

  @override
  String get sealDownloadPdf => 'Export PDF';

  @override
  String get sealBackHome => 'Back to home';

  @override
  String get sealPdfComingSoon => 'PDF export is being prepared for release.';

  @override
  String get rsStep3 => 'STEP 6 OF 6 — REVIEW & SEAL';

  @override
  String get rsReadTitle => 'Read it as your family will';

  @override
  String get rsReadSubtitle => 'Check every line. After sealing, changes need a reopen (Standard and above).';

  @override
  String get rsHeirsTitle => 'Heirs & shares — computed to the fara\'id';

  @override
  String get rsEditHeirs => 'Edit heirs';

  @override
  String get rsNoHeirs => 'No heirs recorded.';

  @override
  String get rsBequestsTitle => 'Bequests — the free third';

  @override
  String get rsEditBequests => 'Edit bequests';

  @override
  String get rsBequestNone => 'None — up to a third may be left outside the shares.';

  @override
  String get rsWithinCap => 'Within the ⅓ cap.';

  @override
  String get rsMessageTitle => 'Words for my family';

  @override
  String get rsEditMessage => 'Edit message';

  @override
  String get rsNoMessage => 'No personal message added yet.';

  @override
  String get rsPeopleTitle => 'Witnesses & trustee';

  @override
  String get rsEditPeople => 'Edit people';

  @override
  String get rsNoneAdded => 'none added';

  @override
  String rsWitnessTrusteeLine(String witnesses, String trustees) {
    return 'Witnesses: $witnesses   ·   Trustee: $trustees (code sent on sealing)';
  }

  @override
  String get rsWitnessesInline => 'Witnesses:';

  @override
  String get rsTrusteeInline => 'Trustee:';

  @override
  String get rsCodeSentSuffix => '(code sent on sealing)';

  @override
  String get rsDocPreview => 'DOCUMENT PREVIEW';

  @override
  String get rsLastWill => 'Last Will & Testament';

  @override
  String get rsFullText => 'Full text · English + العربية · PDF after sealing';

  @override
  String get rsReviewedConfirm => 'I understand Wasiati provides a fara\'id calculation for guidance and is not a fatwa or legal advice; my estate is divided according to the sharia (fara\'id). I confirm the details above are accurate.';

  @override
  String get rsSealMyWill => 'Seal my will';

  @override
  String get rsSignMyWill => 'Sign my will';

  @override
  String get rsWaitingWitnesses => 'Waiting for witnesses';

  @override
  String rsSignedWaitingNote(Object signed, Object required) {
    return 'You\'ve signed. Your will seals once your witnesses confirm by SMS ($signed of $required signed).';
  }

  @override
  String get rsSignNote => 'Your digital signature locks the will; your witnesses are then asked to confirm by SMS.';

  @override
  String get rsSignedNoWitnesses => 'You\'ve signed. Add your witnesses in the will details so they can confirm by SMS — then you can seal.';

  @override
  String get rsWitnessCodesNote => 'Witness SMS codes are sent the moment you seal.';

  @override
  String get rsVerifyEmailNotice => 'Confirm your email address before sealing — it\'s the address your witnesses, trustee and heirs will be contacted at.';

  @override
  String get rsVerifyEmailCta => 'Verify my email';

  @override
  String get wdMyPrimaryWill => 'My primary will';

  @override
  String wdSealedEstate(String tier) {
    return 'Sealed · $tier estate';
  }

  @override
  String get wdDraftNotSealed => 'Draft — not yet sealed';

  @override
  String get wdReopenToEdit => 'Reopen to edit';

  @override
  String get wdReopenSnack => 'Reopen to edit is available on Standard and above.';

  @override
  String get wdReviseOpened => 'A revision draft has been opened. Your sealed will stays in force until you seal the new version.';

  @override
  String get dashRefOpen => 'View referrals';

  @override
  String get settingsReferrals => 'Referrals & account credit';

  @override
  String get settingsReferralsSub => 'Your invite code, share link and earned credit.';

  @override
  String get wdDownloadPdf => 'Download PDF';

  @override
  String wdExportWaitingOn(String parties) {
    return 'Waiting on: $parties';
  }

  @override
  String wdExportWaitingWitnesses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count witnesses',
      one: '1 witness',
    );
    return '$_temp0';
  }

  @override
  String get wdExportWaitingTrustee => 'trustee';

  @override
  String get wdExportChecking => 'Checking signatures…';

  @override
  String get wdReviewSeal => 'Review & seal ›';

  @override
  String get wdAssetsTitle => 'Assets & debts your heirs should know';

  @override
  String get wdAssetsSubtitle => 'An inventory — accounts, property, and any money owed.';

  @override
  String get wdLegacyTitle => 'Messages for your family';

  @override
  String get wdLegacySubtitle => 'Record video & voice messages — released with your will.';

  @override
  String get wdShariaShares => 'Shares — Fara\'id';

  @override
  String get wdThHeir => 'HEIR';

  @override
  String get wdThBasis => 'BASIS';

  @override
  String get wdThShare => 'SHARE';

  @override
  String get wdNoHeirs => 'No heirs recorded yet.';

  @override
  String get wdTotalToHeirs => 'Total to heirs';

  @override
  String get wdAddBequest => 'Add bequest';

  @override
  String wdBequestUsed(String pct) {
    return '$pct% of estate used';
  }

  @override
  String get wdBequestCap => 'cap 33.3%';

  @override
  String get wdNoBequests => 'No bequests yet — up to a third may be left outside the fara\'id shares.';

  @override
  String get wdAddBequestTitle => 'Add a bequest';

  @override
  String get wdBeneficiary => 'Beneficiary';

  @override
  String get wdPercentOfEstate => '% of estate';

  @override
  String get wdFreeThirdHelper => 'Free third: max 33.33% total';

  @override
  String get wdReviewerNote => 'On your passing, a trustee submits a claim. A Wasiati reviewer verifies it before anything is released — nothing happens automatically.';

  @override
  String get wdMessageHint => 'My dearest family — forgive my shortcomings, keep your prayers, and stay close to one another…';

  @override
  String get wdMessagePartOfWill => 'Part of your will · released with it';

  @override
  String get wdSaveMessage => 'Save message';

  @override
  String get wdMessageSaved => 'Message saved with your will.';

  @override
  String get wdWitnesses => 'Witnesses';

  @override
  String get wdTrustees => 'Trustees';

  @override
  String get wdAddWitnessTitle => 'Add witness';

  @override
  String get wdAddTrusteeTitle => 'Add trustee';

  @override
  String get wdAddWitnessBtn => '+ Add witness';

  @override
  String get wdAddTrusteeBtn => '+ Add trustee';

  @override
  String get wdFullName => 'Full name';

  @override
  String get wdPhone => 'Phone (+…)';

  @override
  String get wdEmailOptional => 'Email (optional)';

  @override
  String get wdInviteUnreached => 'We couldn\'t reach them by text or email — check their number, or contact them yourself.';

  @override
  String get wdResend => 'Resend';

  @override
  String get wdSendCode => 'Send code';

  @override
  String get wdNoneAddedYet => 'None added yet.';

  @override
  String get wdStatusConfirmed => 'Confirmed by SMS';

  @override
  String get wdStatusCodeSent => 'Code sent · awaiting confirmation';

  @override
  String get wdStatusPending => 'Pending — no code sent yet';

  @override
  String get wdIdMatched => 'ID matched';

  @override
  String get wdCodeSentSms => 'Verification code sent by SMS.';

  @override
  String wdCodeSentDev(String code) {
    return 'Code sent (dev): $code';
  }

  @override
  String get wdUnpublish => 'Unpublish';

  @override
  String get wdUnpublishTitle => 'Unpublish this will?';

  @override
  String get wdUnpublishBody => 'The will goes back to draft and is no longer in force. Your signature and every witness signature are cleared — sealing again is a fresh ceremony — and witnesses who signed will be told.';

  @override
  String get wdStepUpSmsSent => 'Enter the confirmation code we sent to your phone by SMS.';

  @override
  String get wdStepUpEmailSent => 'Enter the confirmation code we sent to your email.';

  @override
  String get wdStepUpCodeLabel => 'Confirmation code';

  @override
  String get wdUnpublishDone => 'The will is unpublished and back in draft.';

  @override
  String get wdErrorLoadTitle => 'Could not load this will.';

  @override
  String get assetEyebrow => 'MY PRIMARY WILL — ASSETS';

  @override
  String get assetTitle => 'What should your heirs know about?';

  @override
  String get assetSubtitle => 'An inventory, not valuations — so nothing is lost or forgotten.';

  @override
  String get assetAddButton => 'Add asset';

  @override
  String get assetAddLoan => 'Add loan';

  @override
  String get assetSectionAssets => 'ASSETS';

  @override
  String get assetSectionLoans => 'LOANS & LIABILITIES';

  @override
  String get assetInvTitle => 'Add to the inventory';

  @override
  String get assetInvEditTitle => 'Edit inventory item';

  @override
  String get assetExport => 'Export to Excel';

  @override
  String get assetInvAsset => 'Asset';

  @override
  String get assetInvLoan => 'Loan';

  @override
  String get assetColAsset => 'ASSET';

  @override
  String get assetColCategory => 'CATEGORY';

  @override
  String get assetColHeldWith => 'HELD WITH';

  @override
  String get assetColPhone => 'PHONE';

  @override
  String get assetColEmail => 'EMAIL';

  @override
  String get assetColValue => 'VALUE';

  @override
  String get assetColStatus => 'STATUS';

  @override
  String get assetFieldName => 'NAME';

  @override
  String get assetFieldHeldWith => 'HELD WITH / LENDER';

  @override
  String get assetFieldLender => 'OWED TO / LENDER';

  @override
  String get assetFieldCategory => 'CATEGORY';

  @override
  String get assetFieldValueCurrency => 'VALUE & CURRENCY';

  @override
  String get assetFieldPhone => 'PHONE';

  @override
  String get assetFieldEmail => 'EMAIL';

  @override
  String get assetFieldAccountRef => 'ACCOUNT / IBAN';

  @override
  String get assetHintName => 'e.g. Gold — safe deposit';

  @override
  String get asNameRequired => 'Give this asset a name so your family can identify it.';

  @override
  String get asValueInvalid => 'Enter the value as a number, for example 250,000.';

  @override
  String get assetHintHeldWith => 'e.g. SNB';

  @override
  String get assetHintValue => '250,000';

  @override
  String get assetHintPhone => '+966 55 123 4567';

  @override
  String get assetHintEmail => 'care@bank.com';

  @override
  String get assetHintAccountRef => 'e.g. SA03 8000 0000 6080 1016 7519';

  @override
  String get assetRefHelper => 'Account or IBAN plus a contact, so your heirs know exactly where the asset is and who to call. Shown masked in the list.';

  @override
  String get assetCurrencyHelper => 'The value is recorded in the currency you pick here and posts to your will exactly as entered — no conversion.';

  @override
  String get assetStatusManual => 'Manual';

  @override
  String get assetTotalsTitle => 'ESTATE TOTALS';

  @override
  String get assetTotalAssets => 'Assets';

  @override
  String get assetNetEstate => 'Net estate (after debts)';

  @override
  String get assetRegionNote => 'Canada shows RRSP · TFSA · RESP · RRIF; the US shows 401(k) · IRA · Roth · 529. Debts you owe are settled in full before the fara\'id shares are divided.';

  @override
  String get assetErrorHint => 'Tap a suggestion above to add your first item.';

  @override
  String get assetEmptyHint => 'No assets added yet — tap a suggestion above to start.';

  @override
  String get assetVaultNote => 'Assets link to vault secrets: heirs see the asset exists; only the trustee unlocks the details after a claim is approved.';

  @override
  String get assetZakatTitle => 'Zakat estimate';

  @override
  String get assetZakatSubline => 'as of your hawl date · tap for the full calculation';

  @override
  String get assetZakatCaption => 'estimated zakat due';

  @override
  String get assetAddTitle => 'Add an asset';

  @override
  String get assetLabelField => 'Label (e.g. Apartment, Riyadh)';

  @override
  String get assetKindField => 'Kind';

  @override
  String get assetNotesField => 'Notes (optional)';

  @override
  String assetSuggestedFor(String region) {
    return 'SUGGESTED FOR $region';
  }

  @override
  String get assetDebtsHeading => 'DEBTS & LIABILITIES — settled before shares';

  @override
  String get assetRegionKsa => '🇸🇦 KSA';

  @override
  String get assetRegionCa => '🇨🇦 CANADA';

  @override
  String get assetRegionUs => '🇺🇸 US';

  @override
  String get assetKindRealEstate => 'Real estate';

  @override
  String get assetKindBank => 'Bank / account';

  @override
  String get assetKindPension => 'Pension';

  @override
  String get assetKindVehicle => 'Vehicle';

  @override
  String get assetKindBusiness => 'Business';

  @override
  String get assetKindLiability => 'Debt / owed money';

  @override
  String get assetKindOther => 'Other';

  @override
  String get assetRealEstate => 'Real estate';

  @override
  String get assetBankAccount => 'Bank account';

  @override
  String get assetVehicle => 'Vehicle';

  @override
  String get assetBusiness => 'Business';

  @override
  String get assetGold => 'Gold / jewellery';

  @override
  String get assetEndOfService => 'End-of-service benefits';

  @override
  String get assetGosiPension => 'GOSI pension';

  @override
  String get assetLoanOwed => 'Loan / owed money';

  @override
  String get assetMortgage => 'Mortgage';

  @override
  String get assetCreditCard => 'Credit card balance';

  @override
  String get assetUnpaidZakat => 'Unpaid zakat / dues';

  @override
  String get assetValueField => 'Estimated value (optional)';

  @override
  String get assetAmountOwed => 'Amount owed (optional)';

  @override
  String get assetCurrencyField => 'Currency';

  @override
  String get lgEyebrow => 'LEGACY MESSAGES';

  @override
  String get lgTitle => 'A few words they\'ll keep';

  @override
  String get lgSubtitle => 'Released to your family alongside your will — never before. Say what a document can\'t.';

  @override
  String get lgLoadError => 'We couldn\'t load your wills just now.';

  @override
  String get lgCreateFirst => 'Create your will first — your message is kept with it.';

  @override
  String get lgWrittenMessage => 'Written message';

  @override
  String get lgHint => 'To my family — thank you for everything. When you read this…';

  @override
  String get lgSealedNote => 'Your will is sealed — editing the message reopens it for re-sealing.';

  @override
  String get lgPrivateNote => 'Kept private until your will is released to your heirs.';

  @override
  String get lgMessageSaved => 'Message saved.';

  @override
  String get lgVideoTitle => 'Video & voice messages';

  @override
  String get lgVideoBadge => 'Premium · soon';

  @override
  String get lgVideoBody => 'Record a short video or voice note for each person you name — encrypted end-to-end and released only with your will. We\'re building this on the same encrypted vault your documents already use; it isn\'t switched on yet, so we\'re not pretending it is.';

  @override
  String get lgNotifySnack => 'We\'ll let you know the moment video messages are ready.';

  @override
  String get lgNotifyButton => 'Notify me when it\'s ready';

  @override
  String get lgStartWill => 'Start a will';

  @override
  String get kycTitle => 'Identity verification';

  @override
  String get kycSubtitle => 'Required once before your will can be sealed. Handled by Nafath in Saudi Arabia — or Stripe Identity elsewhere.';

  @override
  String get kycLoadError => 'Could not load your verification status.';

  @override
  String get kycNafathSnack => 'Nafath verification appears when your IP is in Saudi Arabia — enabled at launch.';

  @override
  String get kycVerifiedTitle => 'You\'re verified';

  @override
  String get kycVerifiedBody => 'Your wills can be sealed and your trustee claims will be honoured.';

  @override
  String get kycInProgress => 'Verification in progress';

  @override
  String get kycNeedsRetry => 'Needs another try';

  @override
  String get kycVerifyTitle => 'You\'re not verified yet';

  @override
  String get kycPendingBody => 'We\'re reviewing your documents — usually under two minutes.';

  @override
  String get kycRejectedBody => 'We couldn\'t verify your ID. Please try again with a different document.';

  @override
  String get kycVerifyBody => 'Verify once and your wills can be sealed, and your trustee\'s claims will be honoured.';

  @override
  String get kycVerifyNafath => 'Verify with Nafath';

  @override
  String get kycNafathSub => 'Saudi national digital identity';

  @override
  String get kycContinueVerification => 'Continue verification';

  @override
  String get kycAllStates => 'ALL STATES';

  @override
  String get kycStateUnverified => 'Unverified';

  @override
  String get kycStateUnverifiedSub => 'Verify with Nafath (KSA) or Stripe Identity';

  @override
  String get kycOutsideNote => 'Outside Saudi Arabia? You\'ll be verified with Stripe Identity instead.';

  @override
  String get kycStatePending => 'Pending review';

  @override
  String get kycStatePendingSub => 'Usually under 2 minutes; we notify you';

  @override
  String get kycStateVerified => 'Verified';

  @override
  String get kycStateVerifiedSub => 'Unlocks sealing and claims';

  @override
  String get kycStateRejected => 'Rejected';

  @override
  String get kycStateRejectedSub => 'Reason shown; try again with a different document';

  @override
  String get vaultPassphraseShort => 'Your passphrase must be at least 10 characters.';

  @override
  String get vaultAddSecretTitle => 'Add a secret';

  @override
  String get vaultLabelField => 'Label (e.g. Bank login)';

  @override
  String get vaultSecretField => 'Secret value (password, PIN, key…)';

  @override
  String get vaultSiteField => 'Site or app (optional)';

  @override
  String get vaultUserField => 'Username or email (optional)';

  @override
  String get vaultNotesField => 'Notes (optional — recovery codes, which branch, whom to call)';

  @override
  String get vaultAddHint => 'One entry per account. Record the site or app, the username you sign in with, and the secret itself — the person who will one day need this is not you, and a password with no site and no username helps nobody.';

  @override
  String get vaultEncryptSave => 'Encrypt & save';

  @override
  String get vaultUnlockTitle => 'Vault is locked';

  @override
  String get vaultUnlockSubtitle => 'Everything inside is encrypted on your device. Wasiati can never read it.';

  @override
  String get vaultFaceIdSnack => 'Face ID unlock is enabled on your device at launch.';

  @override
  String get vaultUnlockFaceId => 'Unlock with Face ID';

  @override
  String get vaultOr => 'or passphrase';

  @override
  String get vaultPassphraseHint => 'Your vault passphrase';

  @override
  String get vaultUnlockPassphrase => 'Unlock';

  @override
  String get vaultForgotWarn => 'If you lose your passphrase and Face ID, this vault cannot be recovered — not even by us. That is the point.';

  @override
  String get vaultTitle => 'Vault';

  @override
  String get vaultSubtitle => 'Encrypted on your device before it ever leaves. We store only ciphertext.';

  @override
  String get vaultUnlocked => 'Unlocked';

  @override
  String vaultAutoLockIn(int n) {
    return 'Auto-locks in ${n}s';
  }

  @override
  String get vaultRevealFootnote => 'Reveals hide automatically after 10 seconds.';

  @override
  String get vaultDecryptFailed => 'This secret can’t be decrypted with the current passphrase. It may have been saved under a different one — lock the vault and try another passphrase.';

  @override
  String get vaultAddSecretBtn => 'Add secret';

  @override
  String get vaultLockNow => 'Lock now';

  @override
  String get vaultEmptyTitle => 'Your vault is empty';

  @override
  String get vaultEmptySubtitle => 'Add a secret your family will need — a bank IBAN, a deed, a recovery phrase.';

  @override
  String get vaultWarnCallout => 'If you forget your passphrase, these secrets cannot be recovered — by us or anyone. Consider sharing a hint with your trustee.';

  @override
  String get vaultUpgradeTitle => 'The vault is part of Standard';

  @override
  String get vaultUpgradeBody => 'It keeps account numbers, deeds and passwords encrypted for your family.';

  @override
  String get dcRejectTitle => 'Reject claim';

  @override
  String get dcReason => 'Reason';

  @override
  String get dcRejectReasonRequired => 'A written reason is required to reject.';

  @override
  String get dcReject => 'Reject';

  @override
  String get dcEyebrow => 'ADMIN — DEATH CLAIMS';

  @override
  String get dcTitle => 'Claims queue';

  @override
  String get dcCareNote => 'Human review, always. Rejection requires a reason. Release is a separate, logged action.';

  @override
  String get dcNoPending => 'No pending claims.';

  @override
  String dcSubmittedBy(String phone) {
    return 'Submitted by $phone';
  }

  @override
  String dcSubmittedByFor(String phone, String email) {
    return 'Submitted by $phone · for $email';
  }

  @override
  String get dcCertificateOnFile => 'Certificate on file';

  @override
  String get dcViewCertificate => 'View certificate';

  @override
  String get dcCertificateOpenFailed => 'That certificate could not be opened. Do not approve this claim until you have seen it.';

  @override
  String get dcStartReview => 'Start review';

  @override
  String get dcApprove => 'Approve';

  @override
  String get dcRelease => 'Release';

  @override
  String get dcStatusSubmitted => 'Submitted';

  @override
  String get dcStatusUnderReview => 'Under review';

  @override
  String get dcStatusApproved => 'Approved';

  @override
  String get dcStatusReleased => 'Released';

  @override
  String get dcStatusRejected => 'Rejected';

  @override
  String get navBurialQuotes => 'Burial quotes';

  @override
  String get bqEyebrow => 'ADMIN — BURIAL QUOTES';

  @override
  String get bqTitle => 'Quote requests';

  @override
  String get bqCareNote => 'A request means the client wants a real price. Call mosques and funeral homes in their city, then record the quote here — the client sees it on their Burial page.';

  @override
  String get bqNoPending => 'No quote requests waiting.';

  @override
  String bqRequestedBy(String email) {
    return 'Requested by $email';
  }

  @override
  String bqEstimateLine(String base, String projected, int years) {
    return 'Base $base · projected $projected over $years yrs';
  }

  @override
  String bqQuotedLine(String amount) {
    return 'Quoted: $amount';
  }

  @override
  String get bqStatusRequested => 'Quote requested';

  @override
  String get bqStatusQuoted => 'Quoted';

  @override
  String get bqRecordQuote => 'Record quote';

  @override
  String get bqQuoteDialogTitle => 'Record the sourced quote';

  @override
  String bqAmountLabel(String currency) {
    return 'Amount ($currency)';
  }

  @override
  String get bqNotesLabel => 'Notes (optional)';

  @override
  String get bqNotesHelper => 'e.g. which mosque quoted it and what it covers';

  @override
  String get bqErrorAmountRequired => 'Enter the quoted amount.';

  @override
  String get bqQuoteSaved => 'Quote recorded — the client can now see it.';

  @override
  String get auEyebrow => 'ADMIN — USERS';

  @override
  String auUsersCount(int count) {
    return '$count users';
  }

  @override
  String get auRefresh => 'Refresh';

  @override
  String get auByRegion => 'Users by region';

  @override
  String get auIdVerification => 'ID verification';

  @override
  String get auByRole => 'By role';

  @override
  String get auNoData => 'No data';

  @override
  String get auAllUsers => 'All users';

  @override
  String get auColEmail => 'Email';

  @override
  String get auColPhone => 'Phone';

  @override
  String get auColRegion => 'Region';

  @override
  String get auColRole => 'Role';

  @override
  String get auColId => 'ID';

  @override
  String get auColEmailVerified => 'Email verified';

  @override
  String get auColComp => 'Comp';

  @override
  String get auColLastIp => 'Last IP';

  @override
  String get auColJoined => 'Joined';

  @override
  String get auTitle => 'Users';

  @override
  String get auExportExcel => 'Export to Excel';

  @override
  String get auStatTotalUsers => 'TOTAL USERS';

  @override
  String get auStatSealedWills => 'SEALED WILLS';

  @override
  String get auStatIdVerified => 'ID VERIFIED';

  @override
  String auStatDeltaWeek(int count) {
    return '+$count this week';
  }

  @override
  String auStatInReview(int pct) {
    return '$pct% in review';
  }

  @override
  String get auColUser => 'User';

  @override
  String get auColPlan => 'Plan';

  @override
  String get auColIdentity => 'Identity';

  @override
  String get auPlanFree => 'Free';

  @override
  String get auPlanBasic => 'Basic';

  @override
  String get auPlanStandard => 'Standard';

  @override
  String get auPlanPremium => 'Premium';

  @override
  String get auPlanUltimate => 'Ultimate';

  @override
  String get auCompTitle => 'Comped access';

  @override
  String auCompBody(String email) {
    return 'Grant $email a tier with no payment — investor demos, QA and support accounts run on this.';
  }

  @override
  String get auCompTierLabel => 'Tier';

  @override
  String get auCompGrant => 'Grant';

  @override
  String get auCompRevoke => 'Revoke comp';

  @override
  String get auCompGranted => 'Comp granted.';

  @override
  String get auCompRevoked => 'Comp revoked.';

  @override
  String auCompChip(String tier) {
    return 'Comp · $tier';
  }

  @override
  String get prLoadError => 'Could not load pricing:';

  @override
  String prPlansFor(String region) {
    return 'Plans for $region';
  }

  @override
  String prPricesIn(String currency) {
    return 'Prices in $currency · set by region · admin-editable at runtime';
  }

  @override
  String get prNoPlans => 'No plans configured for this region yet.';

  @override
  String prChoose(String plan) {
    return 'Choose $plan';
  }

  @override
  String get prUltimateTitle => 'Ultimate — burial & funeral planning';

  @override
  String get prNotInRegion => 'NOT IN YOUR REGION';

  @override
  String get prUltimateSub => 'Prepaid burial contributions added to your subscription.';

  @override
  String get prLearnMore => 'Learn more';

  @override
  String get prAlreadySubscribed => 'Already subscribed?';

  @override
  String get prBillingSub => 'Invoices, payment method, cancel anytime.';

  @override
  String get prManageBilling => 'Manage billing';

  @override
  String get prPromoTitle => 'Promo code';

  @override
  String get prPromoHint => 'e.g. RAMADAN30';

  @override
  String get prApply => 'Apply';

  @override
  String get prCouldNotCheck => 'Could not check code.';

  @override
  String get prCodeApplied => 'Code applied';

  @override
  String get prInvalidCode => 'Invalid code';

  @override
  String get prGatedTitle => 'The encrypted vault keeps account numbers, deeds and passwords safe for your family.';

  @override
  String get prGatedSub => 'It\'s part of Standard — shown here as a soft prompt, never a hard wall.';

  @override
  String get prUpgrade => 'Upgrade';

  @override
  String get prBillingMonthly => 'Monthly';

  @override
  String get prBillingAnnual => 'Annual';

  @override
  String get prCycleOnce => 'One-time';

  @override
  String get prCycleYearly => 'Yearly';

  @override
  String get prTwoMonthsFree => '2 months free';

  @override
  String get prOneTimeNote => 'One-time: pay once, keep your will, vault and inventory for life. Updates and re-sealing included; burial contributions still require an active Ultimate subscription.';

  @override
  String get prPlansTitle => 'Plans';

  @override
  String prPlansSubtitle(String region, String currency) {
    return 'Prices set automatically for your region — $region · $currency';
  }

  @override
  String get prCycleYearlySave => 'SAVE 10%';

  @override
  String get prMonthlyCommit => 'All subscription plans carry a minimum one-year, non-refundable commitment. You can upgrade or downgrade between plans on monthly billing only. One-time and yearly options are billed up front.';

  @override
  String prNoUltimateNote(String region) {
    return 'Ultimate is not offered in $region — burial carries no cost here, so there is nothing to pre-plan or finance. It appears automatically for members in the US and Canada.';
  }

  @override
  String get prChoosePlan => 'Choose plan';

  @override
  String get prMostPopular => 'MOST POPULAR';

  @override
  String get prLiveLabel => 'LIVE';

  @override
  String get aiFatal503 => 'AI intake isn\'t switched on for this server yet. You can still build your will by hand.';

  @override
  String get aiResumed => 'Welcome back — your conversation continues where it left off.';

  @override
  String get aiGuidedIntake => 'GUIDED INTAKE';

  @override
  String get aiPremium => 'Premium';

  @override
  String get aiTalkThrough => 'Let\'s talk it through';

  @override
  String get aiComposerHint => 'Type your answer…';

  @override
  String get aiMicListen => 'Speak to Ameen';

  @override
  String get aiMicStop => 'Stop';

  @override
  String get aiMicListening => 'Listening… speak now';

  @override
  String get aiCaptured => 'WHAT I\'VE CAPTURED';

  @override
  String get aiHeirs => 'Heirs';

  @override
  String get aiHeirsNone => 'None yet — I\'ll list them here as we talk.';

  @override
  String get aiAssets => 'Assets';

  @override
  String get aiAssetsNone => 'None yet.';

  @override
  String get aiReadyTitle => 'Ready when you are';

  @override
  String get aiReadyBody => 'I\'ll turn this into a proper will you can review, edit and seal.';

  @override
  String get aiTurnIntoWill => 'Turn this into a will';

  @override
  String get aiHintCard => 'Nothing here is final. Everything you say becomes an editable draft — the Sharia shares are computed for you afterwards.';

  @override
  String get aiGatedBadge => 'Premium feature';

  @override
  String get aiGatedTitle => 'Talk your will into being';

  @override
  String get aiGatedBody => 'Guided intake lets you build your will by conversation instead of forms — describe your family and estate in your own words, and we structure it for you. It\'s part of Premium and Ultimate.';

  @override
  String get aiBuildByHand => 'Build a will by hand';

  @override
  String get prBillingCancelSub => 'Cancel subscription';

  @override
  String get prBillingResume => 'Resume subscription';

  @override
  String get kycVerifyDocument => 'Verify my identity';

  @override
  String get kycUnavailable => 'Identity verification is being switched on. Nothing is needed from you yet.';

  @override
  String get prPromoCheckoutNote => 'Also works at Stripe.';

  @override
  String get prUltimateRegionSub => 'Available in Canada & US only.';

  @override
  String get relBaytAlMal => 'Bayt al-mal (public treasury)';

  @override
  String get burialContributionPeriod => 'Contribution period';

  @override
  String burialContributionSummary(int months, String cost) {
    return '$months equal contributions · total $cost exactly — no interest, no profit.';
  }

  @override
  String get burialTerms => 'This is an estimate, not a payment plan. Nothing has been charged and no money is being held for you yet — prepayment is not available on your account, and we will ask before anything is ever taken. The figures show what a grave in this city costs today and what that would come to each month, so you can plan. When prepayment opens, your contributions would be your own money, held for you and refundable at any time.';

  @override
  String get cwMadhhabMalikiShafii => 'Mālikī / Shāfiʿī — classical view';

  @override
  String get refTitle => 'Invite a friend';

  @override
  String get refSubtitle => 'They get 10% off. You earn 2.5% of their first year or one-time purchase.';

  @override
  String get refYourCode => 'Your referral code';

  @override
  String get refCopyLink => 'Copy link';

  @override
  String get refCopied => 'Share link copied';

  @override
  String get refInvited => 'Invited';

  @override
  String get refRewarded => 'Rewarded';

  @override
  String get refCapped => 'Capped';

  @override
  String get refCreditAvailable => 'Credit available';

  @override
  String get refCreditHeld => 'Held';

  @override
  String refCreditHeldNote(int days) {
    return 'Referral credit becomes spendable $days days after your friend’s purchase — that covers the refund window.';
  }

  @override
  String get refEarnedThisYear => 'Earned this year';

  @override
  String refYearlyCap(String cap) {
    return 'of $cap yearly cap';
  }

  @override
  String get refHaveCode => 'Have a referral code?';

  @override
  String get refEnterCode => 'Enter code';

  @override
  String get refApply => 'Apply';

  @override
  String get refApplied => 'Referral code applied.';

  @override
  String refCodeChip(String code) {
    return 'Referral code $code will be applied';
  }

  @override
  String get refTerms => 'Applies to annual and one-time plans only. Monthly plans do not qualify.';

  @override
  String get refLoadError => 'Couldn’t load your referral details.';

  @override
  String get refHistoryTitle => 'Credit history';

  @override
  String get refHistoryEmpty => 'No credit activity yet.';

  @override
  String get refHistoryError => 'Couldn’t load your credit history.';

  @override
  String get refHistoryReasonReferral => 'Referral reward';

  @override
  String get refHistoryReasonPurchase => 'Applied to a purchase';

  @override
  String get refHistoryReasonAdjustment => 'Adjustment';

  @override
  String get refHistoryReasonRefund => 'Refund';

  @override
  String refHistorySpendable(String date) {
    return 'spendable $date';
  }

  @override
  String get navReferrals => 'Invite a friend';

  @override
  String get navZakat => 'Zakat';

  @override
  String get zakatBackToAssets => '‹ Back to assets';

  @override
  String get zakatBackToDashboard => '‹ Back to dashboard';

  @override
  String get zakatTitle => 'Zakat estimate';

  @override
  String get zakatSubtitle => 'On your cash, bank balances, shares and gold.';

  @override
  String get zakatDue => 'Zakat due';

  @override
  String get zakatNoneDue => 'No zakat due';

  @override
  String zakatBelowNisab(String nisab) {
    return 'Your zakatable wealth is below the nisab of $nisab.';
  }

  @override
  String get zakatBase => 'Zakatable total';

  @override
  String get zakatNisab => 'Nisab (85g of gold)';

  @override
  String get zakatRate => 'Rate — one quarter of one tenth (rubʿ al-ʿushr)';

  @override
  String get zakatHawl => 'Hawl date';

  @override
  String get zakatHawlNotSet => 'Not set';

  @override
  String get zakatSetHawl => 'Set hawl date';

  @override
  String get zakatHawlHijriOnly => 'Hijri only — the day (1–30) and month of your zakat anniversary.';

  @override
  String get zakatHawlDay => 'Day';

  @override
  String get zakatHawlMonth => 'Month';

  @override
  String get zakatHawlSaved => 'Hawl date saved';

  @override
  String get zakatCryptoExcluded => 'Crypto is not counted in the zakat base.';

  @override
  String zakatUnconverted(int count, String currency) {
    return '$count holding(s) in $currency are not counted: we have no fixed exchange rate to your currency and will not guess one.';
  }

  @override
  String get zakatPayNow => 'Pay your zakah';

  @override
  String get zakatDisclaimer => 'This estimate may not be calculated correctly for your situation and is not a religious ruling. It assumes shares are held for trading, excludes your home, vehicles and pension, ignores debts deductible against zakat, and uses an approximate nisab. Real estate held for trade, business inventory and other cases have their own rules — verify with a scholar or your local zakat authority before paying.';

  @override
  String get zakatUnavailable => 'The zakat estimate is unavailable right now.';

  @override
  String get zakatBasisCash => 'Cash on hand — zakatable in full.';

  @override
  String get zakatBasisBank => 'Bank balances — treated as cash.';

  @override
  String get zakatBasisShares => 'Shares — zakatable at their market value, held for trading.';

  @override
  String get zakatBasisGold => 'Gold — zakatable by value.';

  @override
  String get checkinTitle => 'Inactivity check-in';

  @override
  String get checkinSubtitle => 'We will ask, now and then, whether you are still with us. Two unanswered reminders alert your trustee — nothing is released.';

  @override
  String get checkinEnable => 'Enable check-in';

  @override
  String get checkinFrequency => 'How often';

  @override
  String get checkinMonthly => 'Monthly';

  @override
  String get checkinQuarterly => 'Quarterly';

  @override
  String get checkinYearly => 'Yearly';

  @override
  String get checkinLoadError => 'We couldn\'t load your latest check-in settings — showing defaults.';

  @override
  String get checkinLastConfirmed => 'Last confirmed';

  @override
  String get checkinNever => 'Never';

  @override
  String get checkinConfirmNow => 'I am still here';

  @override
  String get checkinConfirmed => 'Thank you. Your reminders have been reset.';

  @override
  String get checkinTrusteeAlerted => 'Your trustee has been alerted that you missed your check-ins.';

  @override
  String get claimPolicyTitle => 'Who may report my death';

  @override
  String get claimPolicyTrustee => 'My trustee only';

  @override
  String get claimPolicyHeirs => 'Heirs, with documents';

  @override
  String get claimPolicyBoth => 'Either';

  @override
  String get claimPolicySaved => 'Saved';

  @override
  String get settingsSaveFailed => 'Could not save that change.';

  @override
  String get hijriMonth1 => 'Muharram';

  @override
  String get hijriMonth2 => 'Safar';

  @override
  String get hijriMonth3 => 'Rabiʿ I';

  @override
  String get hijriMonth4 => 'Rabiʿ II';

  @override
  String get hijriMonth5 => 'Jumada I';

  @override
  String get hijriMonth6 => 'Jumada II';

  @override
  String get hijriMonth7 => 'Rajab';

  @override
  String get hijriMonth8 => 'Shaʿban';

  @override
  String get hijriMonth9 => 'Ramadan';

  @override
  String get hijriMonth10 => 'Shawwal';

  @override
  String get hijriMonth11 => 'Dhu al-Qaʿdah';

  @override
  String get hijriMonth12 => 'Dhu al-Hijjah';

  @override
  String get zakatCatCash => 'Cash';

  @override
  String get zakatCatBank => 'Bank balances';

  @override
  String get zakatCatShares => 'Shares';

  @override
  String get zakatCatGold => 'Gold';

  @override
  String get assetKindCash => 'Cash';

  @override
  String get assetKindShares => 'Shares';

  @override
  String get assetKindGold => 'Gold';

  @override
  String get assetKindCrypto => 'Crypto';

  @override
  String get exportTitle => 'Download your will';

  @override
  String get exportFormat => 'Format';

  @override
  String get exportFormatTable => 'Structured listing';

  @override
  String get exportFormatTableSub => 'Heirs, shares and bequests as tables.';

  @override
  String get exportFormatEssay => 'Narrative will';

  @override
  String get exportFormatEssaySub => 'The same, written as a testamentary essay.';

  @override
  String get wpPreviewHead => 'Preview';

  @override
  String get wpEstateFormat => 'ESTATE FORMAT';

  @override
  String get wpFormatTable => 'Table';

  @override
  String get wpFormatNarrative => 'Narrative';

  @override
  String get wpSharesAs => 'SHARES AS';

  @override
  String get wpSharesPercent => '%';

  @override
  String get wpSharesFraction => 'Fraction';

  @override
  String get wpFormatHelp => 'How your assets & loans read in the exported will — a listed table, or flowing will language written for you.';

  @override
  String get wpPreviewFailed => 'The preview could not be rendered. Please try again.';

  @override
  String get wpPreviewRetry => 'Retry';

  @override
  String get exportLanguage => 'Language';

  @override
  String get exportLangEnglish => 'English';

  @override
  String get exportLangArabic => 'العربية';

  @override
  String get exportDownload => 'Download';

  @override
  String get adminContentTitle => 'Content';

  @override
  String get adminContentSubtitle => 'Edit user-facing strings. Changes publish live over the app’s built-in copy.';

  @override
  String get adminContentKey => 'Key';

  @override
  String get adminContentEn => 'English';

  @override
  String get adminContentAr => 'Arabic';

  @override
  String get adminContentNote => 'Note (optional)';

  @override
  String get adminContentPublished => 'Published';

  @override
  String get adminContentDraft => 'Draft';

  @override
  String get adminContentAdd => 'Add string';

  @override
  String get adminContentEdit => 'Edit';

  @override
  String get adminContentSave => 'Publish';

  @override
  String get adminContentRemove => 'Remove override';

  @override
  String get adminContentRemoved => 'Reverted to the built-in string.';

  @override
  String get adminContentSaved => 'Published live.';

  @override
  String get adminContentHistory => 'History';

  @override
  String get adminContentEmpty => 'No overrides yet. Add one to change a string without an app release.';

  @override
  String get adminContentBothRequired => 'Both English and Arabic are required.';

  @override
  String adminContentEditedBy(String who, String when) {
    return '$who · $when';
  }

  @override
  String get navAdminContent => 'Content';

  @override
  String get wsChooseTitle => 'How would you like to write your will?';

  @override
  String get wsChooseSubtitle => 'Both paths end at the same review — you confirm every detail before anything is sealed.';

  @override
  String get wsAmeenTitle => 'Talk to Ameen';

  @override
  String get wsAmeenSub => 'Answer a few questions in plain words; Ameen drafts your will. Nothing is added without your confirmation.';

  @override
  String get wsAmeenBadge => 'INCLUDED IN YOUR PLAN';

  @override
  String get wsAmeenVerse => 'Al-Ameen — the trustworthy — the name the Prophet ṣallā Allāhu ʿalayhi wa-sallam was known by';

  @override
  String get wsFormTitle => 'Guided form';

  @override
  String get wsFormSub => 'Fill it in yourself, step by step, with a live view of the shares.';

  @override
  String get wsFormMeta => '≈ 5 minutes · autosaves as you go';

  @override
  String get wsChooseNote => 'You can switch anytime — Ameen\'s confirmed items appear in the form, and the form\'s answers are visible to Ameen.';

  @override
  String get wsAmeenPremium => 'Premium feature';

  @override
  String get vaultExport => 'Export';

  @override
  String get vaultExportWarnTitle => 'Export secrets as readable text?';

  @override
  String get vaultExportWarnBody => 'The file this creates is NOT encrypted — anyone who can read it holds every secret in this vault. Save it only somewhere as safe as the vault itself, such as a home safe or a bank deposit box, and delete the file once it has served its purpose.';

  @override
  String get vaultExportConfirm => 'Export as plain text';

  @override
  String vaultExportHeader(String date) {
    return 'Wasiati vault — exported $date';
  }

  @override
  String get vaultExportHeaderWarn => 'This file is not encrypted. Anyone who can read it can read every secret below. Delete it after use.';

  @override
  String vaultExportDone(int count) {
    return 'Exported $count secrets to wasiati-vault.txt. Delete the file once it has served its purpose.';
  }

  @override
  String vaultExportSkipped(int count) {
    return '$count items could not be decrypted and were left out.';
  }

  @override
  String get vaultImport => 'Import passwords';

  @override
  String get vaultImportTitle => 'Import from Chrome or Apple Passwords';

  @override
  String get vaultImportHow => 'Export your passwords to a CSV, then paste its contents below. Everything is encrypted on this device before it is saved — the text you paste never leaves your device unencrypted.';

  @override
  String get vaultImportPaste => 'Paste your exported CSV here';

  @override
  String vaultImportPreview(int count) {
    return '$count passwords found';
  }

  @override
  String get vaultImportNone => 'No passwords found — is this a Chrome or Apple Passwords export?';

  @override
  String vaultImportSkipped(int count) {
    return '$count rows skipped (no password).';
  }

  @override
  String vaultImportRun(int count) {
    return 'Import $count';
  }

  @override
  String get vaultImporting => 'Importing…';

  @override
  String vaultImportDone(int count) {
    return 'Imported $count passwords.';
  }

  @override
  String get vaultImportDeleteFile => 'Now delete the exported CSV file from your device — it is not encrypted.';

  @override
  String get vidTitle => 'Video messages';

  @override
  String get vidSubtitle => 'A recorded message for your family, released with your will. Encrypted; only you can see it until then.';

  @override
  String vidStorage(String used, String quota) {
    return '$used of $quota used';
  }

  @override
  String get vidStorageFull => 'Your 1 GB storage is full. Delete a video, or email us for a secure upload link.';

  @override
  String get vidNone => 'No videos yet.';

  @override
  String get vidAdd => 'Add a video';

  @override
  String get vidUploadFile => 'Upload a file';

  @override
  String get vidRecord => 'Record now';

  @override
  String get vidRecordSoon => 'Recording is coming soon — upload a file for now.';

  @override
  String get vidDelete => 'Delete';

  @override
  String get vidDeleted => 'Video deleted.';

  @override
  String get vidUnavailable => 'Video storage isn’t enabled yet.';

  @override
  String get vidDeleteConfirm => 'Delete this video? This cannot be undone.';

  @override
  String get vidBadType => 'Please choose an MP4, WEBM or MOV file.';

  @override
  String get vidUploaded => 'Video uploaded.';

  @override
  String get vidPlay => 'Play video';

  @override
  String get vidPlayError => 'Could not open this video. Please try again.';

  @override
  String get vidScanPending => 'This video is still being checked. Try again shortly.';

  @override
  String get vidScanFailed => 'This video failed a security check and cannot be played.';

  @override
  String get vrTitle => 'Record a message';

  @override
  String get vrStart => 'Start recording';

  @override
  String get vrStop => 'Stop';

  @override
  String get vrPause => 'Pause';

  @override
  String get vrResume => 'Resume';

  @override
  String get vrPauseFailed => 'That could not be paused. Your recording is still running.';

  @override
  String vrTimeLeft(Object time) {
    return '$time left';
  }

  @override
  String get vrMaxLengthReached => 'One hour reached — your recording is saved and ready to review.';

  @override
  String get vrRetake => 'Retake';

  @override
  String get vrUse => 'Use this video';

  @override
  String get vrPermission => 'Camera and microphone access is needed to record.';

  @override
  String get vrNoCamera => 'No camera found on this device.';

  @override
  String get vrBusy => 'Your camera is in use by another app. Close it and try again.';

  @override
  String get vrInsecure => 'Recording needs a secure (https) connection.';

  @override
  String get vrUnsupported => 'This browser can\'t record video. Try Chrome, Edge or Safari — or upload a file instead.';

  @override
  String get vrFailed => 'Recording stopped unexpectedly. Please try again.';

  @override
  String get vrTooLarge => 'That recording is too large to upload. Record a shorter message, or upload a file instead.';

  @override
  String get vrRecording => 'Recording…';

  @override
  String get vrUploading => 'Uploading…';

  @override
  String get authContinueGoogle => 'Google';

  @override
  String get authContinueApple => 'Apple';

  @override
  String get authUsePasskey => 'Continue with passkey';

  @override
  String get authContinueNafath => 'Continue with Nafath';

  @override
  String get authContinueEmail => 'Continue with email';

  @override
  String get authRecommended => 'RECOMMENDED';

  @override
  String get authOr => 'or';

  @override
  String get authGoogleFailed => 'Google sign-in did not complete. Please try again.';

  @override
  String get authGoogleMisconfigured => 'Google sign-in is not fully set up on this app yet. Please use another method.';

  @override
  String get authMethodSoon => 'This sign-in option isn’t enabled in this build yet — use email for now.';

  @override
  String authDetectedRegion(String info) {
    return 'Detected region: $info';
  }

  @override
  String get lndHeroTitle => 'Don’t let two nights pass without a will!';

  @override
  String get lndHeroSub => 'Honored in minutes — shares computed, secrets vaulted, your words delivered to the people you love.';

  @override
  String get lndCtaStart => 'Start my will';

  @override
  String get lndCtaPlans => 'See plans';

  @override
  String get lndWhyTitle => 'Why Wasiati';

  @override
  String get lndWhy1t => 'Your whole legacy, one place';

  @override
  String get lndWhy1d => 'Will, vault, zakat estimate, video messages and burial wishes — everything your family will need, kept together and always current.';

  @override
  String get lndWhy2t => 'Your language, your school of thought';

  @override
  String get lndWhy2d => 'Fully Arabic or English — down to the exported will. Shares follow the majority view of the scholars, or your own school: Hanafi, Maliki, Shafi’i or Hanbali.';

  @override
  String get lndWhy3t => 'It doesn’t stop at sealing';

  @override
  String get lndWhy3d => 'Gentle check-ins while you live; at claim time a human reviews the documents, then your will, vault and videos reach your heirs.';

  @override
  String get lndWhy4t => 'Minutes, not billable hours';

  @override
  String get lndWhy4d => 'Four guided steps, live shares as you type, sealed today — at a fraction of a lawyer’s fee, in Arabic or English, with Nafath sign-in.';

  @override
  String get lndWhy5t => 'Simple, by design';

  @override
  String get lndWhy5d => 'One plain question at a time — no legal jargon, no forms that feel like court. If it isn’t needed, you’re never asked.';

  @override
  String get lndDisclaimer => 'Wasiati is not a law firm, and its employees are not lawyers. Nothing on this site is intended to create a lawyer–client relationship, and your use of Wasiati does not and will not create one between you and Wasiati. Wasiati is not a substitute for the advice of a lawyer and does not give legal advice or legal recommendations of any kind. We provide a service that lets you answer a series of questions and complete your own will. For more information, see our Disclaimer & Terms of Use.';

  @override
  String get lndLegalLink => 'Disclaimer & Terms of Use';

  @override
  String get lndPrivacyLink => 'Privacy Policy';

  @override
  String get lndCopyright => '© 2026 Wasiati Inc.';

  @override
  String get prPerMonth => '/mo';

  @override
  String get prPerYear => '/yr';

  @override
  String get prUltimateNotOneTime => 'Ultimate is a subscription. Its burial pre-planning is funded by contributions over 3, 5 or 10 years, so it isn’t available as a one-time purchase — choose Monthly or Yearly to include it.';

  @override
  String get billingTitle => 'Billing';

  @override
  String get billingSubtitle => 'Your plan, payment method and invoices.';

  @override
  String get billingCurrentPlan => 'CURRENT PLAN';

  @override
  String billingRenewsOn(String date, String price) {
    return 'Renews $date · $price';
  }

  @override
  String billingRenewsOnPlain(String date) {
    return 'Renews $date';
  }

  @override
  String billingEndsOn(String date) {
    return 'Access ends $date';
  }

  @override
  String get billingCancelling => 'Cancelling at period end — your will and vault stay yours.';

  @override
  String billingPastDueLine(String date) {
    return 'Payment failed on $date';
  }

  @override
  String get billingPastDueHelp => 'We couldn’t charge your card and will retry. Update your card below to keep your plan — after several failed attempts it is cancelled.';

  @override
  String get billingPaymentMethod => 'PAYMENT METHOD';

  @override
  String get billingChangeCard => 'Change card';

  @override
  String get billingCardOnFile => 'Card on file';

  @override
  String get billingNoCard => 'No card saved';

  @override
  String get billingCardUnavailable => 'Card management is unavailable on this environment.';

  @override
  String get billingInvoices => 'INVOICES';

  @override
  String get billingNoInvoices => 'No invoices yet. Your receipts appear here after your first payment.';

  @override
  String get billingPaid => 'PAID';

  @override
  String get billingRefunded => 'REFUNDED';

  @override
  String billingCreditApplied(String amount) {
    return '$amount paid from account credit';
  }

  @override
  String get billingProviderNote => 'Payments and card data are handled by Stripe — Wasiati never stores your card.';

  @override
  String get billingNoPlanTitle => 'You have no active subscription';

  @override
  String get billingNoPlanBody => 'Choose a plan to start. Your will and vault stay yours either way.';

  @override
  String get billingSeePlans => 'See plans';

  @override
  String get billingInvoiceError => 'Could not download that invoice.';

  @override
  String get billingCancelConfirmTitle => 'Cancel your subscription?';

  @override
  String get billingCancelConfirmBody => 'Your access continues to the end of the period you have paid for. Your will and vault stay yours. Any burial contributions stop and are returned to you.';

  @override
  String get billingCancelConfirmKeep => 'Keep my plan';

  @override
  String get billingCancelled => 'Your subscription will end at the close of this period.';

  @override
  String get billingResumed => 'Your subscription will continue.';

  @override
  String get billingLoadError => 'Could not load your billing details.';

  @override
  String get portalTitle => 'Heir & trustee portal';

  @override
  String get portalSub => 'Read-only access for heirs and the trustee. It opens only after a human reviewer approves the claim and the will is released.';

  @override
  String get portalRoleHeir => 'I am an heir';

  @override
  String get portalRoleTrustee => 'I am the trustee';

  @override
  String get portalEmailPh => 'Email registered in the will';

  @override
  String get portalContinue => 'Continue';

  @override
  String get portalCodeTitle => 'Confirm it\'s you';

  @override
  String get portalCodeSub => 'Enter the 6-digit code sent to your registered mobile.';

  @override
  String get portalCodeSubEmail => 'Enter the 6-digit code sent to your registered email address.';

  @override
  String portalCodeResendWait(int seconds) {
    return 'You can ask for another code in ${seconds}s';
  }

  @override
  String get portalCodeResendReady => 'Didn\'t get it?';

  @override
  String get portalCodeResend => 'Send another code';

  @override
  String get portalChipHeir => 'HEIR';

  @override
  String get portalChipTrustee => 'TRUSTEE';

  @override
  String get portalReadOnly => 'READ-ONLY';

  @override
  String get portalSignOut => 'Exit portal';

  @override
  String get portalPendingTitle => 'Claim under review';

  @override
  String get portalPendingSub => 'A human reviewer is checking the documents. Access opens the moment the claim is approved and released — we\'ll notify you.';

  @override
  String get portalApprovedTitle => 'Approved — awaiting release';

  @override
  String get portalApprovedSub => 'The claim was approved. The will is released once every registered heir confirms — or the trustee overrides.';

  @override
  String get heirApprovalsTitle => 'HEIR RELEASE CONFIRMATIONS';

  @override
  String get heirConfirmBtn => 'Confirm release of the will';

  @override
  String get heirConfirmedNote => 'Your confirmation is recorded';

  @override
  String get portalWaitOthers => 'Waiting for the remaining confirmations — or a trustee override.';

  @override
  String get trusteeOverrideBtn => 'Override — release without full confirmations';

  @override
  String get overrideOnNote => 'Trustee override recorded — release is unlocked.';

  @override
  String get portalConfirmedMark => 'Confirmed';

  @override
  String get portalAwaitingMark => 'Awaiting';

  @override
  String get portalRejectedTitle => 'This claim was not approved';

  @override
  String get portalRejectedSub => 'A reviewer could not approve the claim from the documents provided. If you believe this is a mistake, reply to the message we sent you and we will look again.';

  @override
  String get portalIstirjaa => 'إِنَّا لِلَّهِ وَإِنَّا إِلَيْهِ رَاجِعُونَ';

  @override
  String heirTitle(String estateName) {
    return 'The will of $estateName has been released to you';
  }

  @override
  String get heirSub => 'The claim was verified and approved. Everything below is now yours to see — take your time.';

  @override
  String get wordsTitle => 'WORDS FOR MY FAMILY';

  @override
  String get heirSharesTitle => 'DIVISION OF THE ESTATE';

  @override
  String get heirBequestsTitle => 'BEQUESTS';

  @override
  String get heirVideoTitle => 'A video message for you';

  @override
  String heirVideoMeta(String date) {
    return 'Recorded $date';
  }

  @override
  String get heirVideoOpen => 'Play the video message';

  @override
  String get heirNoWords => 'No written message was left on this will.';

  @override
  String get portalDebtsNote => 'Debts are settled before shares are distributed.';

  @override
  String get portalLoadError => 'Could not load this will. Please use the link we sent you.';

  @override
  String get portalReportDeath => 'I need to report a death';

  @override
  String get pcLookupTitle => 'Report a death';

  @override
  String get pcLookupSub => 'If someone you know has died and you believe they left a will with us, tell us how to find them. We will contact the people named on the will directly — we cannot tell you whether a will exists.';

  @override
  String get pcDeceasedLbl => 'THE PERSON WHO HAS DIED';

  @override
  String get pcDeceasedPh => 'Their email address or mobile number';

  @override
  String get pcClaimantLbl => 'YOU';

  @override
  String get pcClaimantPh => 'Your own email address or mobile number';

  @override
  String get pcLookupBtn => 'Continue';

  @override
  String get pcAckTitle => 'Thank you';

  @override
  String get pcAckBody => 'If a will exists, we\'ve notified the people named on it. Anyone named will receive a message with a link to continue. Nothing else is needed from you now.';

  @override
  String get pcAckClose => 'Done';

  @override
  String get pcInviteTitle => 'Begin the release of a will';

  @override
  String get pcInviteSub => 'You are named on a will held with us, and someone has asked us to begin the process of releasing it. Take your time — nothing is released until a person here has reviewed it.';

  @override
  String get pcNameLbl => 'YOUR FULL NAME';

  @override
  String get pcNamePh => 'Your full legal name';

  @override
  String get pcCertTitle => 'Death certificate';

  @override
  String get pcCertSub => 'A photograph or scan of the death certificate. A reviewer checks it by hand; nothing is released automatically.';

  @override
  String get pcCertChoose => 'Attach the certificate';

  @override
  String get pcCertUploading => 'Sending…';

  @override
  String pcCertAttached(String fileName) {
    return '$fileName attached';
  }

  @override
  String get pcCertRequired => 'The certificate is needed before this can be sent.';

  @override
  String pcCertTooLarge(String size) {
    return 'That file is larger than $size. Please attach a smaller photograph or scan.';
  }

  @override
  String get pcCertBadType => 'That file type cannot be accepted. Please attach a PDF or a photograph.';

  @override
  String get pcCertOnce => 'This link carries one certificate. If this is the wrong file, reply to the message we sent you and we will send a fresh link.';

  @override
  String get pcSubmitBtn => 'Send for review';

  @override
  String get pcDoneTitle => 'We have it';

  @override
  String get pcDoneSub => 'A reviewer will look at the certificate by hand. We will write to you when there is news — you do not need to do anything else. May Allah ease this for you.';

  @override
  String get pcLinkInvalidTitle => 'This link is no longer valid';

  @override
  String get pcLinkInvalidSub => 'The link may have expired or already been used. If you still need to report a death, you can start again.';

  @override
  String get pcStartOver => 'Start again';

  @override
  String get burialEstimateOnlyNote => 'Estimate only — no payment has been set up.';

  @override
  String get tcTitle => 'You have been named a trustee';

  @override
  String get tcSub => 'Assalamu alaikum. The owner of a will held with Wasiati has asked you to be its trustee.';

  @override
  String get tcDuties => 'As trustee you would: confirm their passing to Wasiati, start the claim with the death certificate, and see the will released to their heirs. You never see the will\'s contents while they are alive.';

  @override
  String get tcAcceptBtn => 'Accept the role';

  @override
  String get tcDecline => 'Decline';

  @override
  String get tcCodeSub => 'Enter the 6-digit code we sent to the mobile number on the will.';

  @override
  String get tcDoneTitle => 'You are now the trustee';

  @override
  String get tcDoneSub => 'May you never be needed. We\'ll only contact you for annual confirmation — and, one day, for the claim.';

  @override
  String get wcTitle => 'You have been asked to witness a will';

  @override
  String get wcSub => 'Assalamu alaikum. The owner of a will held with Wasiati has named you as one of its witnesses.';

  @override
  String get wcDuties => 'As a witness you confirm, under your legal name, that the owner declared this to be their will, made freely. You do not see the will\'s contents — only that it was made.';

  @override
  String get wcLegalNameLbl => 'Your legal name';

  @override
  String get wcLegalNamePh => 'Exactly as on your ID';

  @override
  String get wcLegalNameHelp => 'It must match the name the owner put on the will, or the signature will not be recorded.';

  @override
  String get wcSignBtn => 'Continue to sign';

  @override
  String get wcCodeSub => 'Enter the 6-digit code we sent to the mobile number on the will. Entering it records your witness signature.';

  @override
  String get wcDoneTitle => 'Your witness signature is recorded';

  @override
  String get wcDoneSub => 'JazakAllahu khairan — your part is done. Nothing more is needed from you.';

  @override
  String get confirmClosePage => 'You can close this page.';

  @override
  String get confirmDeclinedTitle => 'No action was taken';

  @override
  String get confirmDeclinedSub => 'Nothing has been recorded or sent. If you change your mind, open the link from the SMS again.';

  @override
  String get confirmLinkInvalidTitle => 'This link is no longer valid';

  @override
  String get confirmLinkInvalidSub => 'The link may be incomplete, or the invitation may have been withdrawn. Please contact the person who named you.';

  @override
  String get portalWillPdfTitle => 'THE WILL ITSELF';

  @override
  String get portalWillPdfSub => 'The executed will, as it was sealed. Keep a copy — you may need it for a court, a bank or a land registry.';

  @override
  String get portalWillPdfDownload => 'Download the will (PDF)';

  @override
  String get passkeyErrorUnsupported => 'This browser doesn’t support passkeys. Use another sign-in method.';

  @override
  String get passkeyErrorCancelled => 'Passkey sign-in was cancelled — or this device has no passkey for Wasiati yet. You can add one in Settings after signing in.';

  @override
  String get passkeyErrorRegisterCancelled => 'Passkey setup was cancelled before it finished. Nothing was saved.';

  @override
  String get passkeyErrorAlreadyRegistered => 'This device already holds a passkey for your account — you can sign in with it now.';

  @override
  String get passkeyErrorGeneric => 'The passkey attempt didn’t complete. Try again, or use another sign-in method.';

  @override
  String get settingsAddPasskey => 'Add a passkey';

  @override
  String get settingsAddPasskeySub => 'Sign in with your face, fingerprint or device PIN — no code needed';

  @override
  String get pkSetupTitle => 'Sign in without a code';

  @override
  String get pkSetupBlurb => 'One more step, and it saves you every time after';

  @override
  String get pkSetupWhy => 'Use Face ID, Touch ID or Windows Hello to sign in. No text message, nothing to wait for — and it cannot be phished.';

  @override
  String get pkSetupCta => 'Set up';

  @override
  String get pkSetupSkip => 'Not now';

  @override
  String get pkSetupLater => 'Your password still works, and you can set this up any time in Settings.';

  @override
  String get passkeyAdded => 'Passkey added — you can now use it to sign in on this device.';

  @override
  String get mfaResendSent => 'A new code is on its way.';

  @override
  String get adminContentKeyHelp => 'Only strings the app can actually show are listed.';

  @override
  String get wdContinueDraft => 'Continue your draft';

  @override
  String get commonBackToLegacy => 'Messages to my family';

  @override
  String get cwToReview => 'Continue to review';

  @override
  String get rsGuardianTitle => 'Guardianship';

  @override
  String get wdocTitle => 'Your will, as it will be read';

  @override
  String get wdocSubtitle => 'The document itself — the same file the download produces. Choose how it reads below.';

  @override
  String get wdViewDocument => 'View document';

  @override
  String get wdocSigningNote => 'You sign by confirming below; your two witnesses and your trustee then confirm by SMS. Nothing is released until all three have.';

  @override
  String wdocOf(Object name) {
    return 'of $name';
  }

  @override
  String wdocWillNumber(Object id) {
    return 'Will #$id';
  }

  @override
  String wdocSealedMeta(Object date) {
    return 'sealed $date';
  }

  @override
  String wdocWitnessesConfirmed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count witnesses confirmed',
      one: '1 witness confirmed',
    );
    return '$_temp0';
  }

  @override
  String get wdocDraftSubtitle => 'Draft — not yet sealed';

  @override
  String get wdocWordsTitle => 'Words for my family';

  @override
  String get wdocWishesTitle => 'Funeral & burial wishes';

  @override
  String get wdocEstateTitle => 'Assets & liabilities';

  @override
  String get wdocNetEstate => 'Net estate';

  @override
  String get wdocEstateNote => 'Estate inventory as recorded at sealing; debts are settled before the shares are distributed.';

  @override
  String get wdocEssayAssetsLead => 'I declare that, as of the sealing of this will, I own the following assets: ';

  @override
  String get wdocEssayLiabilitiesLead => 'I further declare the following debts and obligations, to be settled from my estate before any distribution: ';

  @override
  String wdocEssayHeldWith(Object institution) {
    return ', held with $institution';
  }

  @override
  String wdocEssayValuedAt(Object amount) {
    return ', valued at approximately $amount';
  }

  @override
  String wdocEssayOwedTo(Object institution) {
    return ', owed to $institution';
  }

  @override
  String wdocEssayInAmount(Object amount) {
    return ', in the amount of $amount';
  }

  @override
  String wdocEssayNetEstate(Object amount) {
    return 'After settlement of these obligations, my net estate today amounts to approximately $amount.';
  }

  @override
  String get wdocEssayListJoin => '; ';

  @override
  String get wdocEssayListJoinLast => '; and ';

  @override
  String get wdocEssayNetJoin => ' and ';

  @override
  String get wdocDivisionTitle => 'Division of the estate';

  @override
  String get wdocNoHeirs => 'No heirs recorded.';

  @override
  String get wdocBequest => 'Bequest';

  @override
  String get wdocBequestBasis => 'From the free third — outside the fara’id';

  @override
  String get wdocWitnessesTitle => 'Witnesses & trustee';

  @override
  String get wdocWitnessesCol => 'Witnesses';

  @override
  String get wdocTrusteeCol => 'Trustee';

  @override
  String get wdocWitnessRole => 'Witness';

  @override
  String get wdocTrusteeRole => 'Trustee';

  @override
  String get wdocTestatorRole => 'Testator';

  @override
  String get wdocSignedDigitally => 'Signed digitally';

  @override
  String get wdocPending => 'pending';

  @override
  String get wdocPendingCode => 'pending code';

  @override
  String get wdocNoneRecorded => 'None recorded.';

  @override
  String get wdocSealLine => 'Sealed & witnessed via Wasiati';

  @override
  String get wdocGuidance => 'The fara’id shares herein are computed for guidance and are not a fatwa or legal advice; the estate is divided according to the sharia (fara’id) per the school selected by the testator.';

  @override
  String get vrLensFront => 'Front camera';

  @override
  String get vrLensBack => 'Back camera';

  @override
  String get vrSwitchCamera => 'Switch camera';

  @override
  String get vrReviewTake => 'Your recording';

  @override
  String get vrPlaybackFailed => 'That recording cannot be previewed here, but it did save — you can still use it.';

  @override
  String get vrCameraOff => 'Turn camera off';

  @override
  String get vrCameraOn => 'Turn camera on';

  @override
  String get vrCameraOffNote => 'Camera off — your webcam light should be out.';

  @override
  String get cwExpandAll => 'Expand all';

  @override
  String get cwCollapseAll => 'Collapse all';

  @override
  String get cwHeirNeedsDetails => 'Needs details';

  @override
  String get portalAcceptTrusteeTitle => 'Accept your trusteeship';

  @override
  String get portalAcceptTrusteeBody => 'You were named trustee of this will, but you have not yet accepted the role. Accept it to open the estate and to act on behalf of the family.';

  @override
  String get portalAcceptTrusteeBtn => 'Accept the trusteeship';

  @override
  String get portalAssetRef => 'REFERENCE';

  @override
  String get portalInventoryNote => 'Account references and contacts are shown in full so you can locate each asset. This list is erased with the rest of the estate at the end of the retrieval window — save what you need now.';

  @override
  String get apiOffline => 'Cannot reach the server. Check your connection.';

  @override
  String dcGateWaitingHeirs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count heirs have not confirmed',
      one: '1 heir has not confirmed',
    );
    return '$_temp0';
  }

  @override
  String dcGateWindow(String when) {
    return 'Safety window opens $when';
  }

  @override
  String get dcGateNotSealed => 'This will was never sealed';

  @override
  String get dcGateNoTrustee => 'No trustee has confirmed';

  @override
  String get dcGateOverride => 'Heir confirmations overridden by a trustee';

  @override
  String get dcGateReadyNote => 'Everything release requires is satisfied.';

  @override
  String get vaultPassphraseWrong => 'That passphrase does not open this vault. Nothing was changed — check it and try again.';
}
