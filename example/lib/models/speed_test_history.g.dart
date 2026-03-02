// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'speed_test_history.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SpeedTestHistoryAdapter extends TypeAdapter<SpeedTestHistory> {
  @override
  final int typeId = 0;

  @override
  SpeedTestHistory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SpeedTestHistory(
      timestamp: fields[0] as DateTime,
      result: fields[1] as SpeedTestResultData,
    );
  }

  @override
  void write(BinaryWriter writer, SpeedTestHistory obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.timestamp)
      ..writeByte(1)
      ..write(obj.result);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeedTestHistoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SpeedTestResultDataAdapter extends TypeAdapter<SpeedTestResultData> {
  @override
  final int typeId = 1;

  @override
  SpeedTestResultData read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SpeedTestResultData(
      downloadMbps: fields[0] as double?,
      uploadMbps: fields[1] as double?,
      latencyMs: fields[2] as double?,
      jitterMs: fields[3] as double?,
      packetLossPercent: fields[4] as double?,
      loadedLatencyMs: fields[5] as double?,
      quality: fields[6] as NetworkQualityData,
      metadata: fields[7] as NetworkMetadataData?,
    );
  }

  @override
  void write(BinaryWriter writer, SpeedTestResultData obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.downloadMbps)
      ..writeByte(1)
      ..write(obj.uploadMbps)
      ..writeByte(2)
      ..write(obj.latencyMs)
      ..writeByte(3)
      ..write(obj.jitterMs)
      ..writeByte(4)
      ..write(obj.packetLossPercent)
      ..writeByte(5)
      ..write(obj.loadedLatencyMs)
      ..writeByte(6)
      ..write(obj.quality)
      ..writeByte(7)
      ..write(obj.metadata);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeedTestResultDataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class NetworkQualityDataAdapter extends TypeAdapter<NetworkQualityData> {
  @override
  final int typeId = 2;

  @override
  NetworkQualityData read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NetworkQualityData(
      streaming: fields[0] as ScenarioQualityData,
      gaming: fields[1] as ScenarioQualityData,
      rtc: fields[2] as ScenarioQualityData,
    );
  }

  @override
  void write(BinaryWriter writer, NetworkQualityData obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.streaming)
      ..writeByte(1)
      ..write(obj.gaming)
      ..writeByte(2)
      ..write(obj.rtc);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkQualityDataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ScenarioQualityDataAdapter extends TypeAdapter<ScenarioQualityData> {
  @override
  final int typeId = 3;

  @override
  ScenarioQualityData read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ScenarioQualityData(
      scenario: fields[0] as String,
      gradeIndex: fields[1] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ScenarioQualityData obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.scenario)
      ..writeByte(1)
      ..write(obj.gradeIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScenarioQualityDataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class NetworkMetadataDataAdapter extends TypeAdapter<NetworkMetadataData> {
  @override
  final int typeId = 4;

  @override
  NetworkMetadataData read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NetworkMetadataData(
      networkName: fields[0] as String?,
      connectedVia: fields[1] as String?,
      serverLocation: fields[2] as String?,
      ipAddress: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, NetworkMetadataData obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.networkName)
      ..writeByte(1)
      ..write(obj.connectedVia)
      ..writeByte(2)
      ..write(obj.serverLocation)
      ..writeByte(3)
      ..write(obj.ipAddress);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkMetadataDataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
