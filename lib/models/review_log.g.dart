// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_log.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReviewLogAdapter extends TypeAdapter<ReviewLog> {
  @override
  final int typeId = 2;

  @override
  ReviewLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReviewLog(
      cardId: fields[1] as String,
      collectionId: fields[2] as String,
      rating: fields[3] as int,
      reviewedAt: fields[4] as DateTime,
      id: fields[0] as String?,
      durationMs: fields[5] as int? ?? 0,
      mode: fields[6] as String? ?? 'srs',
      previousState: fields[7] as int? ?? 0,
      previousDue: fields[8] as DateTime?,
      scheduledDays: fields[9] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, ReviewLog obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.cardId)
      ..writeByte(2)
      ..write(obj.collectionId)
      ..writeByte(3)
      ..write(obj.rating)
      ..writeByte(4)
      ..write(obj.reviewedAt)
      ..writeByte(5)
      ..write(obj.durationMs)
      ..writeByte(6)
      ..write(obj.mode)
      ..writeByte(7)
      ..write(obj.previousState)
      ..writeByte(8)
      ..write(obj.previousDue)
      ..writeByte(9)
      ..write(obj.scheduledDays);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
