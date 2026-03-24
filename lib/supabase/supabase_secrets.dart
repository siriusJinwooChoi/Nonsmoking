/// 스토어 배포용 Supabase 연결 정보.
///
/// `flutter build appbundle` 시 `--dart-define`을 넘기지 않으면 이 값이 사용됩니다.
/// **반드시** Supabase 대시보드 → Settings → API 의 **Project URL** 과 **anon public** 키를
/// 아래에 입력하세요. (anon 키는 RLS로 보호되는 한 클라이언트에 포함해도 됩니다.)
///
/// 로컬에서만 dart-define을 쓰는 경우에는 이 파일을 비워 두어도 됩니다.
const String kEmbeddedSupabaseUrl =
    'https://aylqjjwhpqisgvxultel.supabase.co';

const String kEmbeddedSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF5bHFqandocHFpc2d2eHVsdGVsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQwODYzNTEsImV4cCI6MjA4OTY2MjM1MX0.M7vHd9AVyym9SxNNF8u8XyCvFGg0_GlidoGCJK5awxo';
