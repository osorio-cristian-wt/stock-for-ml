package com.stockforml.stock_for_ml

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (no FlutterActivity): requerido por local_auth
// para mostrar el prompt biométrico (BiometricPrompt usa FragmentActivity).
class MainActivity : FlutterFragmentActivity()
