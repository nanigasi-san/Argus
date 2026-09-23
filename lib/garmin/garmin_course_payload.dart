class GarminCoursePayload {
  const GarminCoursePayload({
    required this.courseId,
    required this.armedUntil,
    required this.vertexCount,
    required this.originLatE7,
    required this.originLonE7,
    required this.data,
    required this.checksum,
  });

  final String courseId;
  final int armedUntil;
  final int vertexCount;
  final int originLatE7;
  final int originLonE7;
  final String data;
  final String checksum;

  int get bytes => data.length;

  Map<String, Object> toMap() => {
        'type': 'argus-course',
        'v': 1,
        'courseId': courseId,
        'armedUntil': armedUntil,
        'vertexCount': vertexCount,
        'originLatE7': originLatE7,
        'originLonE7': originLonE7,
        'bytes': bytes,
        'data': data,
        'checksum': checksum,
      };
}
