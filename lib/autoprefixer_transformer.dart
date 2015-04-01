// Copyright (c) 2014, the autoprefixer_transformer project authors. Please see
// the AUTHORS file for details. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// Transfomer that parses css and adds vendor prefixes to CSS rules.
library autoprefixer_transformer;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:barback/barback.dart';

/// Transformer Options:
///
/// * [executable] Path to the autoprefixer executable. DEFAULT: `'autoprefixer'`
/// * [browsers] Browsers you want to target. DEFAULT: `'> 1%'`
/// * [source_map] Generate source map in release mode. DEFAULT: `false`
class TransformerOptions {
  static const String _defaultExecutable = 'autoprefixer';
  static const List<String> _defaultBrowsers = const ['> 1%'];
  static const bool _defaultSourceMap = false;

  final String executable;
  final List<String> browsers;
  final bool sourceMap;

  TransformerOptions(this.executable, this.browsers, this.sourceMap);

  factory TransformerOptions.parse(Map configuration) {
    config(key, defaultValue) {
      var value = configuration[key];
      return value != null ? value : defaultValue;
    }

    return new TransformerOptions(
        config('executable', _defaultExecutable),
        config('browsers', _defaultBrowsers),
        config('source_map', _defaultSourceMap));
  }
}

/// Parses css and adds vendor prefixes to CSS rules.
class AutoprefixerTransformer extends Transformer implements DeclaringTransformer {
  final BarbackSettings _settings;
  final TransformerOptions _options;

  AutoprefixerTransformer.asPlugin(BarbackSettings s)
      : _settings = s,
        _options = new TransformerOptions.parse(s.configuration);

  final String allowedExtensions = '.css';

  Future apply(Transform transform) async {
    final asset = transform.primaryInput;
    final flags = ['--browsers', _options.browsers.join(', ')];
    if (_settings.mode == BarbackMode.DEBUG || _options.sourceMap) {
      flags.add('--map');
    }
    final Process process = await Process.start(_options.executable, flags);
    await process.stdin.addStream(asset.read());
    await process.stdin.close();
    final exitCode = await process.exitCode;
    if (exitCode == 0) {
      transform.addOutput(new Asset.fromStream(asset.id, process.stdout));
    } else {
      final errorString = await process.stderr.transform(UTF8.decoder).fold('', (a, b) => a + b);
      transform.logger.error(errorString, asset: asset.id);
    }
  }

  Future declareOutputs(DeclaringTransform transform) {
    transform.declareOutput(transform.primaryId);
    return new Future.value();
  }
}
