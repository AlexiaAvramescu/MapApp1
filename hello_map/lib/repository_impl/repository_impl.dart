import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gem_kit/api/gem_addressinfo.dart';
import 'package:gem_kit/api/gem_coordinates.dart';
import 'package:gem_kit/api/gem_geographicarea.dart';
import 'package:gem_kit/api/gem_landmark.dart';
import 'package:gem_kit/api/gem_landmarkstore.dart';
import 'package:gem_kit/api/gem_landmarkstoreservice.dart';
import 'package:gem_kit/api/gem_mapviewpreferences.dart';
import 'package:gem_kit/api/gem_searchpreferences.dart';
import 'package:gem_kit/api/gem_types.dart';
import 'package:gem_kit/gem_kit_basic.dart';
import 'package:gem_kit/gem_kit_map_controller.dart';
import 'package:hello_map/landmark_info.dart';
import 'package:hello_map/repositories/repository.dart';
import 'package:gem_kit/api/gem_searchservice.dart';
import 'dart:ui' as ui;

import 'package:hello_map/utility.dart';

class RepositoryImpl implements Repository {
  final GemMapController mapController;
  late SearchService gemSearchService;
  LandmarkStoreService? landmarkStoreService;
  LandmarkStore? favoritesStore;
  List<Landmark> favorites = [];
  VoidCallback? FavoritesUpdateCallBack;

  late Completer<List<Landmark>> completer;

  @override
  set favoritesUpdateCallBack(VoidCallback function) => FavoritesUpdateCallBack = function;

  RepositoryImpl({required this.mapController}) {
    SearchService.create(mapController.mapId).then((service) => gemSearchService = service);
    LandmarkStoreService.create(mapController.mapId).then((value) {
      landmarkStoreService = value;

      String favoritesStoreName = 'Favorites';

      landmarkStoreService!.getLandmarkStoreByName(favoritesStoreName).then((value) => favoritesStore = value);

      landmarkStoreService!.createLandmarkStore(favoritesStoreName).then((value) => favoritesStore ??= value);
    });
  }

  @override
  Coordinates transformScreenToWgs(double x, double y) =>
      mapController.transformScreenToWgs(XyType(x: x.toInt(), y: y.toInt()))!;

  @override
  Future<List<Landmark>> search(String text, Coordinates coordinates,
      {SearchPreferences? preferences, RectangleGeographicArea? geographicArea}) async {
    completer = Completer<List<Landmark>>();

    gemSearchService.search(text, coordinates, (err, results) async {
      if (err != GemError.success || results == null) {
        completer.complete([]);
        return;
      }

      final size = await results.size();
      List<Landmark> searchResults = [];

      for (int i = 0; i < size; i++) {
        final gemLmk = await results.at(i);

        searchResults.add(gemLmk);
      }

      if (!completer.isCompleted) completer.complete(searchResults);
    });

    return await completer.future;
  }

  @override
  Future<Uint8List?> decodeLandmarkIcon(Landmark landmark) {
    final data = landmark.getImage(100, 100);
    Completer<Uint8List?> c = Completer<Uint8List?>();

    int width = 100;
    int height = 100;

    ui.decodeImageFromPixels(data, width, height, ui.PixelFormat.rgba8888, (ui.Image img) async {
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        c.complete(null);
      }
      final list = data!.buffer.asUint8List();
      c.complete(list);
    });

    return c.future;
  }

  @override
  Future<String> getAddressFromLandmark(Landmark landmark) async {
    final addressInfo = landmark.getAddress();
    final street = addressInfo.getField(EAddressField.StreetName);
    final city = addressInfo.getField(EAddressField.City);
    final country = addressInfo.getField(EAddressField.Country);

    return '$street $city $country';
  }

  @override
  Future<void> centerOnCoordinates(Coordinates coordinates) async {
    final animation = GemAnimation(type: EAnimation.AnimationLinear);

    // Use the map controller to center on coordinates
    await mapController.centerOnCoordinates(coordinates, animation: animation);
  }

  @override
  Future<LandmarkInfo> getPanelInfo(Landmark focusedLandmark) async {
    late Uint8List? iconFuture;
    late String nameFuture;
    late Coordinates coordsFuture;
    late String coordsFutureText;
    late List<LandmarkCategory> categoriesFuture;

    iconFuture = await _decodeLandmarkIcon(focusedLandmark);
    nameFuture = focusedLandmark.getName();
    coordsFuture = focusedLandmark.getCoordinates();
    coordsFutureText = "${coordsFuture.latitude.toString()}, ${coordsFuture.longitude.toString()}";
    categoriesFuture = focusedLandmark.getCategories();

    return LandmarkInfo(
        image: iconFuture,
        name: nameFuture,
        categoryName: categoriesFuture.isNotEmpty ? categoriesFuture.first.name! : '',
        formattedCoords: coordsFutureText);
  }

  Future<Uint8List?> _decodeLandmarkIcon(Landmark landmark) async {
    final data = landmark.getImage(100, 100);

    return decodeImageData(data);
  }

  @override
  void deactivateAllHighlights() => mapController.deactivateAllHighlights();

  @override
  Future<bool> checkIfFavourite({required Landmark focusedLandmark}) async {
    final focusedLandmarkCoords = focusedLandmark.getCoordinates();
    final favourites = await favoritesStore!.getLandmarks();
    final favoritesSize = await favourites.size();

    for (int i = 0; i < favoritesSize; i++) {
      final lmk = await favourites.at(i);
      final coords = lmk.getCoordinates();

      if (focusedLandmarkCoords.latitude == coords.latitude && focusedLandmarkCoords.longitude == coords.longitude) {
        return true;
      }
    }

    return false;
  }

  @override
  Future<void> onFavoritesTap({required bool isLandmarkFavorite, required Landmark focusedLandmark}) async {
    if (isLandmarkFavorite) {
      await favoritesStore!.removeLandmark(focusedLandmark);
      favorites.removeWhere((element) => element == focusedLandmark);
    } else {
      await favoritesStore!.addLandmark(focusedLandmark);
      favorites.add(focusedLandmark);
    }
    FavoritesUpdateCallBack!();
  }

  @override
  Future<Landmark?> registerLandmarkTapCallback(Point<num> pos) async {
    // Select the object at the tap position.
    await mapController.selectMapObjects(pos);

    // Get the selected landmarks.
    final landmarks = await mapController.cursorSelectionLandmarks();

    final landmarksSize = await landmarks.size();

    // Check if there is a selected Landmark.
    if (landmarksSize == 0) {
      return null;
    }

    // Highlight the landmark on the map.
    mapController.activateHighlight(landmarks);

    final lmk = await landmarks.at(0);

    return lmk;
  }

  @override
  List<Landmark> getFavorites() => favorites;
}
