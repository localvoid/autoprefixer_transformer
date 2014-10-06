// Copyright (c) 2014, the autoprefixer_transformer project authors. Please see
// the AUTHORS file for details. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// Transfomer that parses css and adds vendor prefixes to CSS rules.
library autoprefixer_transformer;

import 'dart:async';
import 'dart:io';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as ospath;

/// Transformer Options:
///
/// * [executable] Path to the autoprefixer executable. DEFAULT: `'autoprefixer'`
/// * [browsers] Browsers you want to target. DEFAULT: `'> 1%'`
class TransformerOptions {
  static const _defaultExecutable = 'autoprefixer';
  static final _defaultBrowsers = ['> 1%'];

  final String executable;
  final List<String> browsers;

  TransformerOptions(this.executable, this.browsers);

  factory TransformerOptions.parse(Map configuration) {
    config(key, defaultValue) {
      var value = configuration[key];
      return value != null ? value : defaultValue;
    }

    return new TransformerOptions(
        config('executable', _defaultExecutable),
        config('browsers', _defaultBrowsers));
  }
}

/// Parses css and adds vendor prefixes to CSS rules.
class Transformer extends AggregateTransformer implements
    DeclaringAggregateTransformer {
  final BarbackSettings _settings;
  final TransformerOptions _options;

  Transformer.asPlugin(BarbackSettings s)
      : _settings = s,
        _options = new TransformerOptions.parse(s.configuration);

  String classifyPrimary(AssetId id) {
    if (id.extension == '.css') {
      return id.toString();
    } else if (id.extension == '.map') {
      var outPath = ospath.withoutExtension(id.path);
      if (ospath.extension(outPath) == '.css') {
        return '${id.package}|${outPath}';
      }
    }
    return null;
  }

  Future apply(AggregateTransform transform) {
    return transform.primaryInputs.toList().then((assets) {
      findAsset(extension) {
        var asset = assets.where((a) => a.id.extension == extension);
        if (asset.isNotEmpty) {
          return asset.first;
        }
        return null;
      }

      var cssAsset = findAsset('.css');
      var mapAsset = findAsset('.map');

      if (cssAsset == null) {
        return null;
      }

      return Directory.systemTemp.createTemp(
          'autoprefixer-transformer-').then((dir) {
        var cssFileSink;
        var mapFileSink;

        return new Future.sync(() {
          var futures = [];

          var cssFilename = ospath.basename(cssAsset.id.path);
          var cssPath = ospath.join(dir.path, cssFilename);
          cssFileSink = new File(cssPath).openWrite();
          var cssWriteFuture = cssFileSink.addStream(cssAsset.read());
          futures.add(cssWriteFuture);

          var mapFilename;
          var mapWriteFuture;

          if (mapAsset != null) {
            mapFilename = ospath.basename(mapAsset.id.path);
            mapFileSink = new File(
                ospath.join(dir.path, mapFilename)).openWrite();
            mapWriteFuture = mapFileSink.addStream(mapAsset.read());
            futures.add(mapWriteFuture);
          }

          return Future.wait(futures).then((results) {
            return _autoprefixer(
                _options.executable,
                cssPath,
                _options.browsers);
          }).then((results) {
            transform.addOutput(new Asset.fromBytes(cssAsset.id, results[0]));
            transform.addOutput(
                new Asset.fromBytes(cssAsset.id.addExtension('.map'), results[1]));
          });
        }).whenComplete(() {
          var futures = [];
          if (cssFileSink != null) {
            futures.add(cssFileSink.close());
          }
          if (mapFileSink != null) {
            futures.add(mapFileSink.close());
          }
          return Future.wait(futures);
        }).whenComplete(() {
          return dir.delete(recursive: true);
        });
      });
    });
  }

  Future declareOutputs(DeclaringAggregateTransform transform) {
    return transform.primaryIds.take(2).toList().then((assets) {
      var cssAssets = assets.where((a) => a.extension == '.css');
      if (cssAssets.isNotEmpty) {
        transform.declareOutput(cssAssets.first);
        transform.declareOutput(cssAssets.first.addExtension('.map'));
      }
    });
  }
}

Future _autoprefixer(String exec, String filepath, List<String> browsers) {
  var browserFlag = browsers.join(', ');
  var flags = ['-m', '-b', browserFlag, filepath];
  return Process.run(exec, flags).then((result) {
    if (result.exitCode == 0) {
      var cssFuture = new File(filepath).readAsBytes();
      var mapFuture = new File(filepath + '.map').readAsBytes();
      return Future.wait([cssFuture, mapFuture]);
    }
    throw new AutoprefixerException(result.stderr);
  }).catchError((ProcessException e) {
    throw new AutoprefixerException(e.toString());
  }, test: (e) => e is ProcessException);
}

class AutoprefixerException implements Exception {
  final String msg;

  AutoprefixerException(this.msg);

  String toString() => msg == null ? 'AutoprefixerException' : msg;
}
