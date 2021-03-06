require "test_helper"

class SerializerTest < ActiveModel::TestCase
  class Model
    def initialize(hash={})
      @attributes = hash
    end

    def read_attribute_for_serialization(name)
      @attributes[name]
    end

    def as_json(*)
      { :model => "Model" }
    end
  end

  class User
    include ActiveModel::SerializerSupport

    attr_accessor :superuser

    def initialize(hash={})
      @attributes = hash.merge(:first_name => "Jose", :last_name => "Valim", :password => "oh noes yugive my password")
    end

    def read_attribute_for_serialization(name)
      @attributes[name]
    end

    def super_user?
      @superuser
    end
  end

  class Post < Model
    def initialize(attributes)
      super(attributes)
      self.comments ||= []
      self.comments_disabled = false
      self.author = nil
    end

    attr_accessor :comments, :comments_disabled, :author
    def active_model_serializer; PostSerializer; end
  end

  class Comment < Model
    def active_model_serializer; CommentSerializer; end
  end

  class UserSerializer < ActiveModel::Serializer
    attributes :first_name, :last_name

    def serializable_hash
      attributes.merge(:ok => true).merge(options[:scope])
    end
  end

  class DefaultUserSerializer < ActiveModel::Serializer
    attributes :first_name, :last_name
  end

  class MyUserSerializer < ActiveModel::Serializer
    attributes :first_name, :last_name

    def serializable_hash
      hash = attributes
      hash = hash.merge(:super_user => true) if my_user.super_user?
      hash
    end
  end

  class CommentSerializer
    def initialize(comment, options={})
      @object = comment
    end

    attr_reader :object

    def serializable_hash
      { :title => @object.read_attribute_for_serialization(:title) }
    end

    def as_json(options=nil)
      options ||= {}
      if options[:root] == false
        serializable_hash
      else
        { :comment => serializable_hash }
      end
    end
  end

  def test_scope_works_correct
    serializer = ActiveModel::Serializer.new :foo, :scope => :bar
    assert_equal serializer.scope, :bar
  end

  def test_attributes
    user = User.new
    user_serializer = DefaultUserSerializer.new(user, {})

    hash = user_serializer.as_json

    assert_equal({
      :default_user => { :first_name => "Jose", :last_name => "Valim" }
    }, hash)
  end

  def test_attributes_method
    user = User.new
    user_serializer = UserSerializer.new(user, :scope => {})

    hash = user_serializer.as_json

    assert_equal({
      :user => { :first_name => "Jose", :last_name => "Valim", :ok => true }
    }, hash)
  end

  def test_serializer_receives_scope
    user = User.new
    user_serializer = UserSerializer.new(user, :scope => {:scope => true})

    hash = user_serializer.as_json

    assert_equal({
      :user => {
        :first_name => "Jose",
        :last_name => "Valim",
        :ok => true,
        :scope => true
      }
    }, hash)
  end

  def test_serializer_receives_url_options
    user = User.new
    user_serializer = UserSerializer.new(user, :url_options => { :host => "test.local" })
    assert_equal({ :host => "test.local" }, user_serializer.url_options)
  end

  def test_serializer_returns_empty_hash_without_url_options
    user = User.new
    user_serializer = UserSerializer.new(user)
    assert_equal({}, user_serializer.url_options)
  end

  def test_pretty_accessors
    user = User.new
    user.superuser = true
    user_serializer = MyUserSerializer.new(user)

    hash = user_serializer.as_json

    assert_equal({
      :my_user => {
        :first_name => "Jose", :last_name => "Valim", :super_user => true
      }
    }, hash)
  end

  class PostSerializer < ActiveModel::Serializer
    attributes :title, :body
    has_many :comments, :serializer => CommentSerializer
  end

  def test_has_many
    user = User.new

    post = Post.new(:title => "New Post", :body => "Body of new post", :email => "tenderlove@tenderlove.com")
    comments = [Comment.new(:title => "Comment1"), Comment.new(:title => "Comment2")]
    post.comments = comments

    post_serializer = PostSerializer.new(post, :scope => user)

    assert_equal({
      :post => {
        :title => "New Post",
        :body => "Body of new post",
        :comments => [
          { :title => "Comment1" },
          { :title => "Comment2" }
        ]
      }
    }, post_serializer.as_json)
  end

  class PostWithConditionalCommentsSerializer < ActiveModel::Serializer
    root :post
    attributes :title, :body
    has_many :comments, :serializer => CommentSerializer

    def include_associations!
      include! :comments unless object.comments_disabled
    end
  end

  def test_conditionally_included_associations
    user = User.new

    post = Post.new(:title => "New Post", :body => "Body of new post", :email => "tenderlove@tenderlove.com")
    comments = [Comment.new(:title => "Comment1"), Comment.new(:title => "Comment2")]
    post.comments = comments

    post_serializer = PostWithConditionalCommentsSerializer.new(post, :scope => user)

    # comments enabled
    post.comments_disabled = false
    assert_equal({
      :post => {
        :title => "New Post",
        :body => "Body of new post",
        :comments => [
          { :title => "Comment1" },
          { :title => "Comment2" }
        ]
      }
    }, post_serializer.as_json)

    # comments disabled
    post.comments_disabled = true
    assert_equal({
      :post => {
        :title => "New Post",
        :body => "Body of new post"
      }
    }, post_serializer.as_json)
  end

  class PostWithMultipleConditionalsSerializer < ActiveModel::Serializer
    root :post
    attributes :title, :body, :author
    has_many :comments, :serializer => CommentSerializer

    def include_comments?
      !object.comments_disabled
    end

    def include_author?
      scope.super_user?
    end
  end

  def test_conditionally_included_associations_and_attributes
    user = User.new

    post = Post.new(:title => "New Post", :body => "Body of new post", :author => 'Sausage King', :email => "tenderlove@tenderlove.com")
    comments = [Comment.new(:title => "Comment1"), Comment.new(:title => "Comment2")]
    post.comments = comments

    post_serializer = PostWithMultipleConditionalsSerializer.new(post, :scope => user)

    # comments enabled
    post.comments_disabled = false
    assert_equal({
      :post => {
        :title => "New Post",
        :body => "Body of new post",
        :comments => [
          { :title => "Comment1" },
          { :title => "Comment2" }
        ]
      }
    }, post_serializer.as_json)

    # comments disabled
    post.comments_disabled = true
    assert_equal({
      :post => {
        :title => "New Post",
        :body => "Body of new post"
      }
    }, post_serializer.as_json)

    # superuser - should see author
    user.superuser = true
    assert_equal({
      :post => {
        :title => "New Post",
        :body => "Body of new post",
        :author => "Sausage King"
      }
    }, post_serializer.as_json)
  end

  class Blog < Model
    attr_accessor :author
  end

  class AuthorSerializer < ActiveModel::Serializer
    attributes :first_name, :last_name
  end

  class BlogSerializer < ActiveModel::Serializer
    has_one :author, :serializer => AuthorSerializer
  end

  def test_has_one
    user = User.new
    blog = Blog.new
    blog.author = user

    json = BlogSerializer.new(blog, :scope => user).as_json
    assert_equal({
      :blog => {
        :author => {
          :first_name => "Jose",
          :last_name => "Valim"
        }
      }
    }, json)
  end

  def test_overridden_associations
    author_serializer = Class.new(ActiveModel::Serializer) do
      attributes :first_name
    end

    blog_serializer = Class.new(ActiveModel::Serializer) do
      def person
        object.author
      end

      has_one :person, :serializer => author_serializer
    end

    user = User.new
    blog = Blog.new
    blog.author = user

    json = blog_serializer.new(blog, :scope => user).as_json
    assert_equal({
      :person => {
        :first_name => "Jose"
      }
    }, json)
  end

  def post_serializer
    Class.new(ActiveModel::Serializer) do
      attributes :title, :body
      has_many :comments, :serializer => CommentSerializer
      has_one :author, :serializer => DefaultUserSerializer
    end
  end

  def test_associations_with_nil_association
    user = User.new
    blog = Blog.new

    json = BlogSerializer.new(blog, :scope => user).as_json
    assert_equal({
      :blog => { :author => nil }
    }, json)

    serializer = Class.new(BlogSerializer) do
      root :blog
    end

    json = serializer.new(blog, :scope => user).as_json
    assert_equal({ :blog =>  { :author => nil } }, json)
  end

  def test_custom_root
    user = User.new
    blog = Blog.new

    serializer = Class.new(BlogSerializer) do
      root :my_blog
    end

    assert_equal({ :my_blog => { :author => nil } }, serializer.new(blog, :scope => user).as_json)
  end

  def test_false_root
    user = User.new
    blog = Blog.new

    serializer = Class.new(BlogSerializer) do
      root false
    end

    assert_equal({ :author => nil }, serializer.new(blog, :scope => user).as_json)

    # test inherited false root
    serializer = Class.new(serializer)
    assert_equal({ :author => nil }, serializer.new(blog, :scope => user).as_json)
  end

  def test_embed_ids
    serializer = post_serializer

    serializer.class_eval do
      root :post
      embed :ids
    end

    post = Post.new(:title => "New Post", :body => "Body of new post", :email => "tenderlove@tenderlove.com")
    comments = [Comment.new(:title => "Comment1", :id => 1), Comment.new(:title => "Comment2", :id => 2)]
    post.comments = comments

    serializer = serializer.new(post)

    assert_equal({
      :post => {
        :title => "New Post",
        :body => "Body of new post",
        :comments => [1, 2],
        :author => nil
      }
    }, serializer.as_json)
  end

  def test_embed_ids_include_true
    serializer_class = post_serializer

    serializer_class.class_eval do
      root :post
      embed :ids, :include => true
    end

    post = Post.new(:title => "New Post", :body => "Body of new post", :email => "tenderlove@tenderlove.com")
    comments = [Comment.new(:title => "Comment1", :id => 1), Comment.new(:title => "Comment2", :id => 2)]
    post.comments = comments

    serializer = serializer_class.new(post)

    assert_equal({
      :post => {
        :title => "New Post",
        :body => "Body of new post",
        :comments => [1, 2],
        :author => nil
      },
      :comments => [
        { :title => "Comment1" },
        { :title => "Comment2" }
      ],
      :authors => []
    }, serializer.as_json)

    post.author = User.new(:id => 1)

    serializer = serializer_class.new(post)

    assert_equal({
      :post => {
        :title => "New Post",
        :body => "Body of new post",
        :comments => [1, 2],
        :author => 1
      },
      :comments => [
        { :title => "Comment1" },
        { :title => "Comment2" }
      ],
      :authors => [{ :first_name => "Jose", :last_name => "Valim" }]
    }, serializer.as_json)
  end

  def test_embed_objects
    serializer = post_serializer

    serializer.class_eval do
      root :post
      embed :objects
    end

    post = Post.new(:title => "New Post", :body => "Body of new post", :email => "tenderlove@tenderlove.com")
    comments = [Comment.new(:title => "Comment1", :id => 1), Comment.new(:title => "Comment2", :id => 2)]
    post.comments = comments

    serializer = serializer.new(post)

    assert_equal({
      :post => {
        :title => "New Post",
        :body => "Body of new post",
        :author => nil,
        :comments => [
          { :title => "Comment1" },
          { :title => "Comment2" }
        ]
      }
    }, serializer.as_json)
  end

  # serialize different typed objects
  def test_array_serializer
    model    = Model.new
    user     = User.new
    comments = Comment.new(:title => "Comment1", :id => 1)

    array = [model, user, comments]
    serializer = array.active_model_serializer.new(array, :scope => {:scope => true})
    assert_equal([
      { :model => "Model" },
      { :last_name => "Valim", :ok => true, :first_name => "Jose", :scope => true },
      { :title => "Comment1" }
    ], serializer.as_json)
  end

  def test_array_serializer_with_root
    comment1 = Comment.new(:title => "Comment1", :id => 1)
    comment2 = Comment.new(:title => "Comment2", :id => 2)

    array = [ comment1, comment2 ]

    serializer = array.active_model_serializer.new(array, :root => :comments)

    assert_equal({ :comments => [
      { :title => "Comment1" },
      { :title => "Comment2" }
    ]}, serializer.as_json)
  end

  def test_array_serializer_with_hash
    hash = {:value => "something"}
    array = [hash]
    serializer = array.active_model_serializer.new(array, :root => :items)
    assert_equal({ :items => [ hash.as_json ]}, serializer.as_json)
  end

  class CustomPostSerializer < ActiveModel::Serializer
    attributes :title
  end

  def test_array_serializer_with_specified_seriailizer
    post1 = Post.new(:title => "Post1", :author => "Author1", :id => 1)
    post2 = Post.new(:title => "Post2", :author => "Author2", :id => 2)

    array = [ post1, post2 ]

    serializer = array.active_model_serializer.new array, :each_serializer => CustomPostSerializer

    assert_equal([
      { :title => "Post1" },
      { :title => "Post2" }
    ], serializer.as_json)
  end

  def test_sets_can_be_serialized
    post1 = Post.new(:title => "Post1", :author => "Author1", :id => 1)
    post2 = Post.new(:title => "Post2", :author => "Author2", :id => 2)

    set = Set.new
    set << post1
    set << post2

    serializer = set.active_model_serializer.new set, :each_serializer => CustomPostSerializer

    as_json = serializer.as_json
    assert_equal 2, as_json.size
    assert as_json.include?({ :title => "Post1" })
    assert as_json.include?({ :title => "Post2" })
  end

  class CustomBlog < Blog
    attr_accessor :public_posts, :public_user
  end

  class CustomBlogSerializer < ActiveModel::Serializer
    has_many :public_posts, :key => :posts, :serializer => PostSerializer
    has_one :public_user, :key => :user, :serializer => UserSerializer
  end

  def test_associations_with_as
    posts = [
      Post.new(:title => 'First Post', :body => 'text'), 
      Post.new(:title => 'Second Post', :body => 'text')
    ]
    user = User.new

    custom_blog = CustomBlog.new
    custom_blog.public_posts = posts
    custom_blog.public_user = user

    serializer = CustomBlogSerializer.new(custom_blog, :scope => { :scope => true })

    assert_equal({
      :custom_blog => {
        :posts => [
          {:title => 'First Post', :body => 'text', :comments => []},
          {:title => 'Second Post', :body => 'text', :comments => []}
        ],
        :user => {
          :first_name => "Jose", 
          :last_name => "Valim", :ok => true, 
          :scope => true
        }
      }
    }, serializer.as_json)
  end

  def test_implicity_detection_for_association_serializers 
    implicit_serializer = Class.new(ActiveModel::Serializer) do
      root :custom_blog
      const_set(:UserSerializer, UserSerializer)
      const_set(:PostSerializer, PostSerializer)

      has_many :public_posts, :key => :posts
      has_one :public_user, :key => :user
    end

    posts = [
      Post.new(:title => 'First Post', :body => 'text', :comments => []), 
      Post.new(:title => 'Second Post', :body => 'text', :comments => [])
    ]
    user = User.new

    custom_blog = CustomBlog.new
    custom_blog.public_posts = posts
    custom_blog.public_user = user

    serializer = implicit_serializer.new(custom_blog, :scope => { :scope => true })

    assert_equal({
      :custom_blog => {
        :posts => [
          {:title => 'First Post', :body => 'text', :comments => []},
          {:title => 'Second Post', :body => 'text', :comments => []}
        ],
        :user => {
          :first_name => "Jose", 
          :last_name => "Valim", :ok => true, 
          :scope => true
        }
      }
    }, serializer.as_json)
  end

  def test_attribute_key
    serializer_class = Class.new(ActiveModel::Serializer) do
      root :user

      attribute :first_name, :key => :firstName
      attribute :last_name, :key => :lastName
      attribute :password
    end

    serializer = serializer_class.new(User.new)

    assert_equal({
      :user => {
        :firstName => "Jose",
        :lastName => "Valim",
        :password => "oh noes yugive my password"
      }
    }, serializer.as_json)
  end

  def setup_model
    Class.new do
      class << self
        def columns_hash
          { "name" => Struct.new(:type).new(:string), "age" => Struct.new(:type).new(:integer) }
        end

        def reflect_on_association(name)
          case name
          when :posts
            Struct.new(:macro, :name).new(:has_many, :posts)
          when :parent
            Struct.new(:macro, :name).new(:belongs_to, :parent)
          end
        end
      end
    end
  end

  def test_schema
    model = setup_model

    serializer = Class.new(ActiveModel::Serializer) do
      class << self; self; end.class_eval do
        define_method(:model_class) do model end
      end

      attributes :name, :age
      has_many :posts, :serializer => Class.new
      has_one :parent, :serializer => Class.new
    end

    assert_equal serializer.schema, {
      :attributes => { :name => :string, :age => :integer },
      :associations => {
        :posts => { :has_many => :posts },
        :parent => { :belongs_to => :parent }
      }
    }
  end

  def test_schema_with_as
    model = setup_model

    serializer = Class.new(ActiveModel::Serializer) do
      class << self; self; end.class_eval do
        define_method(:model_class) do model end
      end

      attributes :name, :age
      has_many :posts, :key => :my_posts, :serializer => Class.new
      has_one :parent, :key => :my_parent, :serializer => Class.new
    end

    assert_equal serializer.schema, {
      :attributes => { :name => :string, :age => :integer },
      :associations => {
        :my_posts => { :has_many => :posts },
        :my_parent => { :belongs_to => :parent }
      }
    }
  end

  def test_embed_id_for_has_one
    author_serializer = Class.new(ActiveModel::Serializer)

    serializer_class = Class.new(ActiveModel::Serializer) do
      embed :ids
      root :post

      attributes :title, :body
      has_one :author, :serializer => author_serializer
    end

    post_class = Class.new(Model) do
      attr_accessor :author
    end

    author_class = Class.new(Model)

    post = post_class.new(:title => "New Post", :body => "It's a new post!")
    author = author_class.new(:id => 5)
    post.author = author

    hash = serializer_class.new(post)

    assert_equal({
      :post => {
        :title => "New Post",
        :body => "It's a new post!",
        :author => 5
      }
    }, hash.as_json)
  end

  def test_embed_objects_for_has_one
    author_serializer = Class.new(ActiveModel::Serializer) do
      attributes :id, :name
    end

    serializer_class = Class.new(ActiveModel::Serializer) do
      root :post

      attributes :title, :body
      has_one :author, :serializer => author_serializer
    end

    post_class = Class.new(Model) do
      attr_accessor :author
    end

    author_class = Class.new(Model)

    post = post_class.new(:title => "New Post", :body => "It's a new post!")
    author = author_class.new(:id => 5, :name => "Tom Dale")
    post.author = author

    hash = serializer_class.new(post)

    assert_equal({
      :post => {
        :title => "New Post",
        :body => "It's a new post!",
        :author => { :id => 5, :name => "Tom Dale" }
      }
    }, hash.as_json)
  end

  def test_root_provided_in_options
    author_serializer = Class.new(ActiveModel::Serializer) do
      attributes :id, :name
    end

    serializer_class = Class.new(ActiveModel::Serializer) do
      root :post

      attributes :title, :body
      has_one :author, :serializer => author_serializer
    end

    post_class = Class.new(Model) do
      attr_accessor :author
    end

    author_class = Class.new(Model)

    post = post_class.new(:title => "New Post", :body => "It's a new post!")
    author = author_class.new(:id => 5, :name => "Tom Dale")
    post.author = author

    assert_equal({
      :blog_post => {
        :title => "New Post",
        :body => "It's a new post!",
        :author => { :id => 5, :name => "Tom Dale" }
      }
    }, serializer_class.new(post, :root => :blog_post).as_json)

    assert_equal({
      :title => "New Post",
      :body => "It's a new post!",
      :author => { :id => 5, :name => "Tom Dale" }
    }, serializer_class.new(post, :root => false).as_json)

    assert_equal({
      :blog_post => {
        :title => "New Post",
        :body => "It's a new post!",
        :author => { :id => 5, :name => "Tom Dale" }
      }
    }, serializer_class.new(post).as_json(:root => :blog_post))

    assert_equal({
      :title => "New Post",
      :body => "It's a new post!",
      :author => { :id => 5, :name => "Tom Dale" }
    }, serializer_class.new(post).as_json(:root => false))
  end

  def test_serializer_has_access_to_root_object
    hash_object = nil

    author_serializer = Class.new(ActiveModel::Serializer) do
      attributes :id, :name

      define_method :serializable_hash do
        hash_object = @options[:hash]
        super()
      end
    end

    serializer_class = Class.new(ActiveModel::Serializer) do
      root :post

      attributes :title, :body
      has_one :author, :serializer => author_serializer
    end

    post_class = Class.new(Model) do
      attr_accessor :author
    end

    author_class = Class.new(Model)

    post = post_class.new(:title => "New Post", :body => "It's a new post!")
    author = author_class.new(:id => 5, :name => "Tom Dale")
    post.author = author

    expected = serializer_class.new(post).as_json
    assert_equal expected, hash_object
  end
  
  def test_embed_ids_include_true_with_root
    serializer_class = post_serializer

    serializer_class.class_eval do
      root :post
      embed :ids, :include => true
      has_many :comments, :key => :comment_ids, :root => :comments
      has_one :author, :serializer => DefaultUserSerializer, :key => :author_id, :root => :author
    end

    post = Post.new(:title => "New Post", :body => "Body of new post", :email => "tenderlove@tenderlove.com")
    comments = [Comment.new(:title => "Comment1", :id => 1), Comment.new(:title => "Comment2", :id => 2)]
    post.comments = comments

    serializer = serializer_class.new(post)

    assert_equal({
    :post => {
      :title => "New Post",
      :body => "Body of new post",
      :comment_ids => [1, 2],
      :author_id => nil
    },
    :comments => [
      { :title => "Comment1" },
      { :title => "Comment2" }
    ],
    :author => []
    }, serializer.as_json)

    post.author = User.new(:id => 1)

    serializer = serializer_class.new(post)

    assert_equal({
    :post => {
      :title => "New Post",
      :body => "Body of new post",
      :comment_ids => [1, 2],
      :author_id => 1
    },
    :comments => [
      { :title => "Comment1" },
      { :title => "Comment2" }
    ],
    :author => [{ :first_name => "Jose", :last_name => "Valim" }]
    }, serializer.as_json)
  end
  
  # the point of this test is to illustrate that deeply nested serializers
  # still side-load at the root.
  def test_embed_with_include_inserts_at_root
    tag_serializer = Class.new(ActiveModel::Serializer) do
      attributes :id, :name
    end

    comment_serializer = Class.new(ActiveModel::Serializer) do
      embed :ids, :include => true
      attributes :id, :body
      has_many :tags, :serializer => tag_serializer
    end

    post_serializer = Class.new(ActiveModel::Serializer) do
      embed :ids, :include => true
      attributes :id, :title, :body
      has_many :comments, :serializer => comment_serializer
    end

    post_class = Class.new(Model) do
      attr_accessor :comments

      define_method :active_model_serializer do
        post_serializer
      end
    end

    comment_class = Class.new(Model) do
      attr_accessor :tags
    end

    tag_class = Class.new(Model)

    post = post_class.new(:title => "New Post", :body => "NEW POST", :id => 1)
    comment1 = comment_class.new(:body => "EWOT", :id => 1)
    comment2 = comment_class.new(:body => "YARLY", :id => 2)
    tag1 = tag_class.new(:name => "lolcat", :id => 1)
    tag2 = tag_class.new(:name => "nyancat", :id => 2)
    tag3 = tag_class.new(:name => "violetcat", :id => 3)

    post.comments = [comment1, comment2]
    comment1.tags = [tag1, tag3]
    comment2.tags = [tag1, tag2]

    actual = ActiveModel::ArraySerializer.new([post], :root => :posts).as_json
    assert_equal({
      :posts => [
        { :title => "New Post", :body => "NEW POST", :id => 1, :comments => [1,2] }
      ],

      :comments => [
        { :body => "EWOT", :id => 1, :tags => [1,3] },
        { :body => "YARLY", :id => 2, :tags => [1,2] }
      ],

      :tags => [
        { :name => "lolcat", :id => 1 },
        { :name => "violetcat", :id => 3 },
        { :name => "nyancat", :id => 2 }
      ]
    }, actual)
  end

  def test_can_customize_attributes
    serializer = Class.new(ActiveModel::Serializer) do
      attributes :title, :body

      def title
        object.title.upcase
      end
    end

    klass = Class.new do
      def read_attribute_for_serialization(name)
        { :title => "New post!", :body => "First post body" }[name]
      end

      def title
        read_attribute_for_serialization(:title)
      end

      def body
        read_attribute_for_serialization(:body)
      end
    end

    object = klass.new

    actual = serializer.new(object, :root => :post).as_json

    assert_equal({
      :post => {
        :title => "NEW POST!",
        :body => "First post body"
      }
    }, actual)
  end

  def test_can_customize_attributes_with_read_attributes
    serializer = Class.new(ActiveModel::Serializer) do
      attributes :title, :body

      def read_attribute_for_serialization(name)
        { :title => "New post!", :body => "First post body" }[name]
      end
    end

    actual = serializer.new(Object.new, :root => :post).as_json

    assert_equal({
      :post => {
        :title => "New post!",
        :body => "First post body"
      }
    }, actual)
  end

  def test_active_support_on_load_hooks_fired
    loaded = nil
    ActiveSupport.on_load(:active_model_serializers) do
      loaded = self
    end
    assert_equal ActiveModel::Serializer, loaded
  end

  def tests_query_attributes_strip_question_mark
    todo = Class.new do
      def overdue?
        true
      end

      def read_attribute_for_serialization(name)
        send name
      end
    end

    serializer = Class.new(ActiveModel::Serializer) do
      attribute :overdue?
    end

    actual = serializer.new(todo.new).as_json

    assert_equal({
      :overdue => true
    }, actual)
  end

  def tests_query_attributes_allow_key_option
    todo = Class.new do
      def overdue?
        true
      end

      def read_attribute_for_serialization(name)
        send name
      end
    end

    serializer = Class.new(ActiveModel::Serializer) do
      attribute :overdue?, :key => :foo
    end

    actual = serializer.new(todo.new).as_json

    assert_equal({
      :foo => true
    }, actual)
  end

  # Set up some classes for polymorphic testing
  class Attachment < Model
    def attachable
      @attributes[:attachable]
    end

    def readable
      @attributes[:readable]
    end

    def edible
      @attributes[:edible]
    end
  end

  def tests_can_handle_polymorphism
    email_serializer = Class.new(ActiveModel::Serializer) do
      attributes :subject, :body
    end

    email_class = Class.new(Model) do
      def self.to_s
        "Email"
      end

      define_method :active_model_serializer do
        email_serializer
      end
    end

    attachment_serializer = Class.new(ActiveModel::Serializer) do
      attributes :name, :url
      has_one :attachable, :polymorphic => true
    end

    email = email_class.new :subject => 'foo', :body => 'bar'

    attachment = Attachment.new :name => 'logo.png', :url => 'http://example.com/logo.png', :attachable => email

    actual = attachment_serializer.new(attachment, {}).as_json

    assert_equal({
      :name => 'logo.png', 
      :url => 'http://example.com/logo.png',
      :attachable => {
        :type => :email,
        :email => { :subject => 'foo', :body => 'bar' }
      }
    }, actual)
  end

  def test_can_handle_polymoprhic_ids
    email_serializer = Class.new(ActiveModel::Serializer) do
      attributes :subject, :body
    end

    email_class = Class.new(Model) do
      def self.to_s
        "Email"
      end

      define_method :active_model_serializer do
        email_serializer
      end
    end

    attachment_serializer = Class.new(ActiveModel::Serializer) do
      embed :ids
      attributes :name, :url
      has_one :attachable, :polymorphic => true
    end

    email = email_class.new :id => 1

    attachment = Attachment.new :name => 'logo.png', :url => 'http://example.com/logo.png', :attachable => email

    actual = attachment_serializer.new(attachment, {}).as_json

    assert_equal({
      :name => 'logo.png', 
      :url => 'http://example.com/logo.png',
      :attachable => {
        :type => :email,
        :id => 1
      }
    }, actual)
  end

  def test_polymorphic_associations_are_included_at_root
    email_serializer = Class.new(ActiveModel::Serializer) do
      attributes :subject, :body, :id
    end

    email_class = Class.new(Model) do
      def self.to_s
        "Email"
      end

      define_method :active_model_serializer do
        email_serializer
      end
    end

    attachment_serializer = Class.new(ActiveModel::Serializer) do
      root :attachment
      embed :ids, :include => true
      attributes :name, :url
      has_one :attachable, :polymorphic => true
    end

    email = email_class.new :id => 1, :subject => "Hello", :body => "World"

    attachment = Attachment.new :name => 'logo.png', :url => 'http://example.com/logo.png', :attachable => email

    actual = attachment_serializer.new(attachment, {}).as_json

    assert_equal({
      :attachment => {
        :name => 'logo.png', 
        :url => 'http://example.com/logo.png',
        :attachable => {
          :type => :email, 
          :id => 1
        }},
      :emails => [{
        :id => 1,
        :subject => "Hello",
        :body => "World"
      }]
    }, actual)
  end

  def test_multiple_polymorphic_associations
    email_serializer = Class.new(ActiveModel::Serializer) do
      attributes :subject, :body, :id
    end

    orange_serializer = Class.new(ActiveModel::Serializer) do
      embed :ids, :include => true

      attributes :plu, :id
      has_one :readable, :polymorphic => true
    end

    email_class = Class.new(Model) do
      def self.to_s
        "Email"
      end

      define_method :active_model_serializer do
        email_serializer
      end
    end

    orange_class = Class.new(Model) do
      def self.to_s
        "Orange"
      end

      def readable
        @attributes[:readable]
      end

      define_method :active_model_serializer do
        orange_serializer
      end
    end

    attachment_serializer = Class.new(ActiveModel::Serializer) do
      root :attachment
      embed :ids, :include => true

      attributes :name, :url

      has_one :attachable, :polymorphic => true
      has_one :readable,   :polymorphic => true
      has_one :edible,     :polymorphic => true
    end

    email  = email_class.new  :id => 1, :subject => "Hello", :body => "World"
    orange = orange_class.new :id => 1, :plu => "3027",  :readable => email

    attachment = Attachment.new({
      :name       => 'logo.png',
      :url        => 'http://example.com/logo.png',
      :attachable => email,
      :readable   => email,
      :edible     => orange
    })

    actual = attachment_serializer.new(attachment, {}).as_json

    assert_equal({
      :emails => [{
        :subject => "Hello",
        :body => "World",
        :id => 1
      }],

      :oranges => [{
        :plu => "3027",
        :id => 1,
        :readable => { :type => :email, :id => 1 }
      }],

      :attachment => {
        :name => 'logo.png',
        :url => 'http://example.com/logo.png',
        :attachable => { :type => :email, :id => 1 },
        :readable => { :type => :email, :id => 1 },
        :edible => { :type => :orange, :id => 1 }
      }
    }, actual)
  end

  def test_raises_an_error_when_a_child_serializer_includes_associations_when_the_source_doesnt
    attachment_serializer = Class.new(ActiveModel::Serializer) do
      attributes :name
    end

    fruit_serializer = Class.new(ActiveModel::Serializer) do
      embed :ids, :include => true
      has_one :attachment, :serializer => attachment_serializer
      attribute :color
    end

    banana_class = Class.new Model do
      def self.to_s
        'banana'
      end

      def attachment
        @attributes[:attachment]
      end

      define_method :active_model_serializer do
        fruit_serializer
      end
    end

    strawberry_class = Class.new Model do
      def self.to_s
        'strawberry'
      end

      def attachment
        @attributes[:attachment]
      end

      define_method :active_model_serializer do
        fruit_serializer
      end
    end

    smoothie = Class.new do
      attr_reader :base, :flavor

      def initialize(base, flavor)
        @base, @flavor = base, flavor
      end
    end

    smoothie_serializer = Class.new(ActiveModel::Serializer) do
      root false
      embed :ids, :include => true

      has_one :base, :polymorphic => true
      has_one :flavor, :polymorphic => true
    end

    banana_attachment = Attachment.new({
      :name => 'banana_blending.md',
      :id => 3,
    })

    strawberry_attachment = Attachment.new({
      :name => 'strawberry_cleaning.doc',
      :id => 4
    })

    banana = banana_class.new :color => "yellow", :id => 1, :attachment => banana_attachment
    strawberry = strawberry_class.new :color => "red", :id => 2, :attachment => strawberry_attachment

    smoothie = smoothie_serializer.new(smoothie.new(banana, strawberry))

    assert_raise ActiveModel::Serializer::IncludeError do
      smoothie.as_json
    end
  end

  def tests_includes_does_not_include_nil_polymoprhic_associations
    post_serializer = Class.new(ActiveModel::Serializer) do
      root :post
      embed :ids, :include => true
      has_one :author, :polymorphic => true
      attributes :title
    end

    post = Post.new(:title => 'Foo')

    actual = post_serializer.new(post).as_json

    assert_equal({
      :post => {
        :title => 'Foo',
        :author => nil
      }
    }, actual)
  end
end
