describe Import, type: :model do
  subject(:import) { build(:import) }

  describe 'associations' do
    it { should have_one_attached(:file) }
  end

  describe 'validations' do
    %i[total_count imported_count failed_count].each do |field|
      it { should validate_presence_of(field) }
      it { should validate_numericality_of(field).only_integer }
      it { should validate_numericality_of(field).is_greater_than_or_equal_to(0) }
    end

    context 'file attachment validation' do
      it 'is invalid without an attached file' do
        import.file.purge
        expect(import).not_to be_valid
      end

      it 'is valid with an attached file' do
        expect(import.file).to be_attached
        expect(import).to be_valid
      end
    end
  end

  describe 'status enum' do
    it 'has valid status values' do
      expect(Import.statuses.keys).to match_array(%w[pending running completed failed])
    end
  end

  describe 'database constraints' do
    it { should have_db_column(:status).of_type(:enum).with_options(null: false, default: 'pending') }

    %i[total_count imported_count failed_count].each do |field|
      it { should have_db_column(field).of_type(:integer).with_options(null: false, default: 0) }
    end

    it { should have_db_column(:error_log).of_type(:text).with_options(array: true, default: []) }
    it { should have_db_column(:started_at).of_type(:datetime) }
    it { should have_db_column(:completed_at).of_type(:datetime) }
    it { should have_db_index(:status) }
  end

  describe '#file_path' do
    it 'returns the correct file path' do
      expect(import.file_path).to eq(ActiveStorage::Blob.service.path_for(import.file.key))
    end
  end

  describe '#run!' do
    let(:company_csv_parser) { instance_double(CompanyCsvParser) }
    let(:file_importer) { instance_double(FileImporter, import: true, imported_objects: [ double, double ], errors: []) }

    before do
      allow(CompanyCsvParser).to receive(:new).with(import.file_path).and_return(company_csv_parser)
      allow(FileImporter).to receive(:new).with(import, company_csv_parser).and_return(file_importer)
    end

    context 'when import is successful' do
      it 'updates status to completed, timestamps and sets imported_count' do
        import.run!

        expect(import.started_at).to be_a(ActiveSupport::TimeWithZone)
        expect(import.completed_at).to be_a(ActiveSupport::TimeWithZone)

        expect(import.status).to eq('completed')
        expect(import.imported_count).to eq(2)
      end
    end

    context 'when import fails' do
      let(:file_importer) { instance_double(FileImporter, import: false, imported_objects: [], errors: [ double(full_messages: 'Error importing') ]) }

      it 'updates status to failed and stores errors' do
        import.run!

        expect(import.status).to eq('failed')
        expect(import.error_log).to include('Error importing')
      end
    end

    context 'when an exception occurs' do
      before do
        allow(file_importer).to receive(:import).and_raise(StandardError.new('Unexpected error'))
      end

      it 'updates status to failed, stores error and raises the exception' do
        expect { import.run! }.to raise_error(StandardError, 'Unexpected error')
        expect(import.status).to eq('failed')
        expect(import.error_log).to include('Unexpected error')
      end
    end
  end
end
