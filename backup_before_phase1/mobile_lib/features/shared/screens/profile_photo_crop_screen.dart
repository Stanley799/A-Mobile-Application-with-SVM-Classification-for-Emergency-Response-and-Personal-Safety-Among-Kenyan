import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/profile_repository.dart';

class ProfilePhotoCropScreen extends StatefulWidget {
  const ProfilePhotoCropScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<ProfilePhotoCropScreen> createState() => _ProfilePhotoCropScreenState();
}

class _ProfilePhotoCropScreenState extends State<ProfilePhotoCropScreen> {
  final _controller = CropController();
  Uint8List? _preview;
  bool _ready = false;
  bool _processing = false;
  String? _error;

  Future<void> _onCropped(CropResult result) async {
    try {
      switch (result) {
        case CropSuccess(:final croppedImage):
          final preview = await compute(prepareProfilePhoto, croppedImage);
          if (mounted) setState(() => _preview = preview);
        case CropFailure():
          throw const FormatException(
            'Unable to crop this photo. Try another image.',
          );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to crop this photo. Try another image.',
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_processing,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _preview == null ? 'Crop profile photo' : 'Preview profile photo',
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _preview != null
                    ? Center(
                        child: SizedBox.square(
                          dimension: 240,
                          child: ClipOval(
                            child: Image.memory(_preview!, fit: BoxFit.cover),
                          ),
                        ),
                      )
                    : Crop(
                        image: widget.bytes,
                        controller: _controller,
                        aspectRatio: 1,
                        withCircleUi: true,
                        interactive: true,
                        fixCropRect: true,
                        onCropped: _onCropped,
                        onStatusChanged: (status) {
                          if (mounted) {
                            setState(() => _ready = status == CropStatus.ready);
                          }
                        },
                        progressIndicator: const CircularProgressIndicator(),
                      ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _processing || (!_ready && _preview == null)
                            ? null
                            : () {
                                if (_preview != null) {
                                  Navigator.of(context).pop(_preview);
                                } else {
                                  setState(() {
                                    _processing = true;
                                    _error = null;
                                  });
                                  _controller.crop();
                                }
                              },
                        icon: _processing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(_preview == null ? Icons.crop : Icons.check),
                        label: Text(
                          _preview == null ? 'Crop Photo' : 'Use Photo',
                        ),
                      ),
                    ),
                    if (_preview != null)
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _preview = null;
                          _ready = false;
                        }),
                        icon: const Icon(Icons.crop),
                        label: const Text('Adjust Crop'),
                      ),
                    TextButton(
                      onPressed: _processing
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
