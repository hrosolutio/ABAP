namespace exam.logistics;

type TransportMode : String enum {
  Air  = 'A';
  Sea  = 'S';
  Rail = 'R';
}

entity Shipments {
  key ID          : UUID;
      customer    : String;
      mode        : TransportMode;
  virtual totalWeight : Decimal(10,2);
  virtual shippingFee : Decimal(10,2);
      packages    : Composition of many Packages on packages.parent = $self;
}

entity Packages {
  key ID       : UUID;
      contents : String;
      weight   : Decimal(10,2);
      parent   : Association to Shipments;
}
