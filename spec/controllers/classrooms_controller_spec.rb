# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClassroomsController, type: :controller do
  let(:classroom) { classroom_org }
  let(:user)      { classroom_teacher }
  let(:student)   { classroom_student }

  before do
    sign_in_as(user)
  end

  describe "GET #index", :vcr do
    context "unauthenticated user" do
      before do
        sign_out
      end

      it "redirects to login_path" do
        get :index
        expect(response).to redirect_to(login_path)
      end
    end

    context "authenticated user with a valid token" do
      it "succeeds" do
        get :index
        expect(response).to have_http_status(:success)
      end

      it "sets the users organization" do
        classroom # call the record so that it is created

        get :index
        expect(assigns(:classrooms).first.id).to eq(classroom.id)
      end
    end

    context "user with admin privilege on the organization but not part of the classroom" do
      before(:each) do
        classroom.users = []
      end

      it "adds the user to the classroom" do
        get :index

        expect(user.classrooms).to include(classroom)
      end
    end

    context "user without admin privilege on the organization" do
      before(:each) do
        sign_in_as(student)
      end

      it "does not add the user to the classroom" do
        get :index

        expect(student.classrooms).to be_empty
      end
    end

    context "authenticated user with an invalid token" do
      before do
        allow(user).to receive(:ensure_no_token_scope_loss).and_return(true)
        user.update_attributes(token: "1234")
      end

      it "logs out user" do
        get :index
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "GET #new", :vcr do
    it "returns success status" do
      get :new
      expect(response).to have_http_status(:success)
    end

    it "has a new organization" do
      get :new
      expect(assigns(:classroom)).to_not be_nil
    end

    it "has an Kaminari::PaginatableArray of the users GitHub organizations that they are an admin of" do
      get :new
      expect(assigns(:users_github_organizations)).to be_kind_of(Kaminari::PaginatableArray)
    end

    it "will not include any organizations that are already apart of classroom" do
      get :new
      expect(assigns(:users_github_organizations)).not_to include([classroom.title, classroom.github_id])
    end
  end

  describe "POST #create", :vcr do
    before do
      request.env["HTTP_REFERER"] = "http://classroomtest.com/orgs/new"
    end

    after(:each) do
      classroom.destroy!
    end

    context "multiple_classrooms_per_org flag not enabled" do
      before do
        GitHubClassroom.flipper[:multiple_classrooms_per_org].disable
      end

      it "will not add an organization that already exists" do
        existing_organization_options = { github_id: classroom.github_id }
        expect do
          post :create, params: { classroom: existing_organization_options }
        end.to_not change(Classroom, :count)
      end
    end

    context "multiple_classrooms_per_org flag is enabled" do
      before do
        GitHubClassroom.flipper[:multiple_classrooms_per_org].enable
      end

      after do
        GitHubClassroom.flipper[:multiple_classrooms_per_org].disable
      end

      it "will add a classroom on same organization" do
        existing_organization_options = { github_id: classroom.github_id }
        expect do
          post :create, params: { classroom: existing_organization_options }
        end.to change(Classroom, :count)
      end
    end

    it "will fail to add an organization the user is not an admin of" do
      new_organization = build(:classroom, github_id: 90)
      new_organization_options = { github_id: new_organization.github_id }

      expect do
        post :create, params: { classroom: new_organization_options }
      end.to_not change(Classroom, :count)
    end

    it "will add an organization that the user is admin of on GitHub" do
      organization_params = { github_id: classroom.github_id, users: classroom.users }
      classroom.destroy!

      expect { post :create, params: { classroom: organization_params } }.to change(Classroom, :count)

      expect(Classroom.last.github_id).to_not be_nil
      expect(Classroom.last.github_global_relay_id).to_not be_nil
    end

    it "will redirect the user to the setup page" do
      organization_params = { github_id: classroom.github_id, users: classroom.users }
      classroom.destroy!

      post :create, params: { classroom: organization_params }

      expect(response).to redirect_to(setup_classroom_path(Classroom.last))
    end
  end

  describe "GET #show", :vcr do
    it "returns success and sets the organization" do
      get :show, params: { id: classroom.slug }

      expect(response.status).to eq(200)
      expect(assigns(:current_classroom)).to_not be_nil
    end
  end

  describe "GET #edit", :vcr do
    it "returns success and sets the organization" do
      get :edit, params: { id: classroom.slug }

      expect(response).to have_http_status(:success)
      expect(assigns(:current_classroom)).to_not be_nil
    end
  end

  describe "GET #invitation", :vcr do
    it "returns success and sets the organization" do
      get :invitation, params: { id: classroom.slug }

      expect(response).to have_http_status(:success)
      expect(assigns(:current_classroom)).to_not be_nil
    end
  end

  describe "PATCH #remove_user", :vcr do
    context "returns 404" do
      it "user is not an org owner" do
        patch :remove_user, params: { id: classroom.slug, user_id: student.id }

        expect(response).to have_http_status(404)
      end

      it "user does not exist" do
        patch :remove_user, params: { id: classroom.slug, user_id: 105 }

        expect(response).to have_http_status(404)
      end
    end

    context "removes user from classroom" do
      before(:each) do
        teacher = create(:user)
        classroom.users << teacher
      end

      it "without assignments" do
        patch :remove_user, params: { id: classroom.slug, user_id: @teacher.id }

        expect(response).to redirect_to(settings_invitations_classroom_path)
        expect(flash[:success]).to be_present
        expect { classroom.users.find(id: @teacher.id) }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "with assignments" do
        assignment = create(:assignment, classroom: classroom, creator: @teacher)

        patch :remove_user, params: { id: classroom.slug, user_id: @teacher.id }

        expect(assignment.reload.creator_id).not_to eq(@teacher.id)
        expect { classroom.users.find(id: @teacher.id) }.to raise_error(ActiveRecord::RecordNotFound)
        expect(response).to redirect_to(settings_invitations_classroom_path)
        expect(flash[:success]).to be_present
      end
    end
  end

  describe "GET #show_groupings", :vcr do
    context "flipper is enabled" do
      before do
        GitHubClassroom.flipper[:team_management].enable
      end

      it "returns success and sets the organization" do
        get :show_groupings, params: { id: classroom.slug }

        expect(response).to have_http_status(:success)
        expect(assigns(:current_classroom)).to_not be_nil
      end

      after do
        GitHubClassroom.flipper[:team_management].disable
      end
    end

    context "flipper is not enabled" do
      it "returns success and sets the organization" do
        get :show_groupings, params: { id: classroom.slug }
        expect(response.status).to eq(404)
      end
    end
  end

  describe "PATCH #update", :vcr do
    it "correctly updates the organization" do
      options = { title: "New Title" }
      patch :update, params: { id: classroom.slug, classroom: options }

      expect(response).to redirect_to(classroom_path(Classroom.find(classroom.id)))
    end
  end

  describe "DELETE #destroy", :vcr do
    it "sets the `deleted_at` column for the organization" do
      classroom # call the record so that it is created

      expect { delete :destroy, params: { id: classroom.slug } }.to change(Classroom, :count)
      expect(Classroom.unscoped.find(classroom.id).deleted_at).not_to be_nil
    end

    it "calls the DestroyResource background job" do
      delete :destroy, params: { id: classroom.slug }

      assert_enqueued_jobs 1 do
        DestroyResourceJob.perform_later(classroom)
      end
    end

    it "redirects back to the index page" do
      delete :destroy, params: { id: classroom.slug }
      expect(response).to redirect_to(classrooms_path)
    end
  end

  describe "GET #invite", :vcr do
    it "returns success and sets the organization" do
      get :invite, params: { id: classroom.slug }

      expect(response.status).to eq(200)
      expect(assigns(:current_classroom)).to_not be_nil
    end
  end

  describe "GET #setup", :vcr do
    it "returns success and sets the organization" do
      get :setup, params: { id: classroom.slug }

      expect(response.status).to eq(200)
      expect(assigns(:current_classroom)).to_not be_nil
    end
  end

  describe "PATCH #setup_organization", :vcr do
    before(:each) do
      options = { title: "New Title" }
      patch :update, params: { id: classroom.slug, classroom: options }
    end

    it "correctly updates the organization" do
      expect(Classroom.find(classroom.id).title).to eql("New Title")
    end

    it "redirects to the invite page on success" do
      expect(response).to redirect_to(classroom_path(Classroom.find(classroom.id)))
    end
  end
end