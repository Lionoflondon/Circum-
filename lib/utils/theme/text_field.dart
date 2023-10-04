import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'colors.dart';

class AppTextInput {
  var brightness =
      SchedulerBinding.instance.platformDispatcher.platformBrightness;
  static Widget input(
      {TextEditingController? controller,
      Function(String val)? onChanged,
      String? labelText,
      String? hintText,
      String? initialValue,
      TextInputType? keyboardType,
      FocusNode? focusNode,
      bool? autofocus,
      bool? autocorrect,
      bool? obscureText,
      bool? enabled,
      int? minLines,
      int? maxLines,
      Widget? prefix,
      Widget? surfix,
      Color? fillColor,
      Color? borderColor,
      Color? activeBorderColor,
      int? maxLength,
      double? borderRadius,
      List<TextInputFormatter>? inputFormatters}) {
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      keyboardType: keyboardType ?? TextInputType.text,
      cursorColor: AppColors.primary,
      focusNode: focusNode,
      enableSuggestions: false,
      autofocus: autofocus ?? false,
      autocorrect: autocorrect ?? false,
      obscureText: obscureText ?? false,

      inputFormatters: inputFormatters,
      maxLines: maxLines,
      minLines: minLines,
      enabled: enabled,

      maxLength: maxLength,
      style: TextStyle(
        color: Colors.white,
        fontFamily: 'OpenSans',
        decoration: TextDecoration.none,
        // fontSize: obscureText != null && obscureText == true ? 14 : 16
      ),
      decoration: InputDecoration(
        fillColor: fillColor ?? AppColors.input,
        filled: true,
        prefixIcon: prefix,
        // suffix: surfix,
        suffixIcon: surfix,
        counterStyle:
            const TextStyle(color: Colors.white, fontFamily: 'OpenSans'),

        // prefix: prefix,
        labelText: labelText,

        labelStyle: const TextStyle(
            // fontFamily: 'Lato',
            fontSize: 14.0,
            fontWeight: FontWeight.w500,
            color: AppColors.textDarkMode),
        hintText: hintText,
        hintStyle: TextStyle(color: AppColors.textDarkMode.withOpacity(0.7)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(borderRadius ?? 0)),
          borderSide: BorderSide(color: activeBorderColor ?? AppColors.primary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(borderRadius ?? 0)),
          borderSide: BorderSide(color: borderColor ?? AppColors.input),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(borderRadius ?? 0)),
          borderSide: const BorderSide(color: AppColors.input),
        ),
      ),

      // validator: (value) =>
      //     state.isValidUsername ? null : 'Fullname is too short',
      onChanged: onChanged,
    );
  }
}
