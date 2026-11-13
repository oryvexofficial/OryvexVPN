import 'package:flutter_test/flutter_test.dart';
import 'package:vexostream_app/pages/model_profile_data.dart';

void main() {
  test('shows the nested personal and physical details used on the website', () {
    final profile = unwrapModelProfile({
      'model': {
        'name': 'Example',
        'personal_details': {'age': 29, 'gender': 'Female', 'country': 'France', 'birth_date': '1997-01-01'},
        'physical_attributes': {'height': '170 cm', 'hair_color': 'Brown', 'eye_color': 'Blue', 'piercings': 'Yes'},
      },
    });
    final personal = modelProfileDetails(profile, 'personal_details');
    final physical = modelProfileDetails(profile, 'physical_attributes');
    expect(personal['age'], '29');
    expect(personal['birth_date'], '1997-01-01');
    expect(personal['country'], 'France');
    expect(physical['height'], '170 cm');
    expect(physical['hair_color'], 'Brown');
    expect(physical['eye_color'], 'Blue');
    expect(physical['piercings'], 'Yes');
  });

  test('unwraps profiles behind data and preserves site detail sections', () {
    final profile = unwrapModelProfile({
      'data': {
        'model': {
          'name': 'Example',
          'country_name': 'Lebanon',
          'personal_details': {'age': '33 years young', 'gender': 'Female', 'career': '2014-2015', 'birth_date': 'Wednesday 10th of February 1993'},
          'physical_attributes': {'height': "5'2\" (158.0 cm)", 'hair_color': 'Dark'},
        },
      },
    });
    final personal = modelProfileDetails(profile, 'personal_details');
    final physical = modelProfileDetails(profile, 'physical_attributes');
    expect(personal['age'], '33 years young');
    expect(personal['country'], 'Lebanon');
    expect(personal['career'], '2014-2015');
    expect(personal['birth_date'], 'Wednesday 10th of February 1993');
    expect(physical['height'], "5'2\" (158.0 cm)");
  });

  test('retains gallery order, resolves image objects and removes duplicates', () {
    expect(modelProfilePhotos({
      'images': ['https://images.example.test/one.jpg', {'url': 'https://images.example.test/two.jpg'}],
      'image_url': 'https://images.example.test/one.jpg',
      'gallery': ['//images.example.test/three.jpg'],
    }), [
      'https://images.example.test/one.jpg',
      'https://images.example.test/two.jpg',
      '//images.example.test/three.jpg',
    ]);
  });

  test('handles missing sections and additional public detail fields', () {
    final model = {'personal_details': {'career': ['Model', 'Performer'], 'languages': 'French'}};
    expect(modelProfileDetails(model, 'personal_details')['career'], 'Model, Performer');
    expect(modelProfileDetails(model, 'personal_details')['languages'], 'French');
    expect(modelProfileDetails(model, 'physical_attributes'), isEmpty);
  });
}
