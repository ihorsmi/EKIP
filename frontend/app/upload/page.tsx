import UploadForm from "../../components/UploadForm";

export default function UploadPage() {
  return (
    <div className="grid gap-4">
      <h2 className="text-xl font-semibold">Document Upload</h2>
      <UploadForm />
    </div>
  );
}
